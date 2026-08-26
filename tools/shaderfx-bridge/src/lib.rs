// Plain FFI surface: call a function, get strings/a manifest back. No
// Librashader runtime backend (GL/Vulkan/D3D/Metal) is linked in and no
// live graphics context is ever touched here -- this is
// librashader-presets + librashader-reflect only, the translation step,
// exactly what spike/src/main.rs already proved works as a standalone
// binary. This just gives that same logic a stable C ABI so a LuaJIT
// `ffi.load`/`ffi.cdef` caller can reach it.

use std::collections::HashMap;
use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::path::Path;

use librashader_common::{FilterMode, WrapMode};
use librashader_presets::{Scaling, ScaleFactor, ScaleType, ShaderFeatures, ShaderPreset};
use librashader_preprocess::ShaderSource;
use librashader_reflect::back::glsl::GlslVersion;
use librashader_reflect::back::targets::GLSL;
use librashader_reflect::back::{CompileShader, FromCompilation};
use librashader_reflect::front::{Glslang, ShaderInputCompiler};
use librashader_reflect::reflect::semantics::{
    Semantic, ShaderSemantics, TextureSemanticMap, TextureSemantics, UniformSemantic,
    UniqueSemanticMap,
};
use librashader_reflect::reflect::ReflectShader;
use serde::Serialize;

fn filter_str(f: FilterMode) -> &'static str {
    match f {
        FilterMode::Linear => "linear",
        FilterMode::Nearest => "nearest",
    }
}

fn wrap_str(w: WrapMode) -> &'static str {
    match w {
        WrapMode::ClampToBorder => "clamp_to_border",
        WrapMode::ClampToEdge => "clamp_to_edge",
        WrapMode::Repeat => "repeat",
        WrapMode::MirroredRepeat => "mirrored_repeat",
    }
}

fn texture_semantics_str(t: TextureSemantics) -> &'static str {
    match t {
        TextureSemantics::Original => "Original",
        TextureSemantics::Source => "Source",
        TextureSemantics::OriginalHistory => "OriginalHistory",
        TextureSemantics::PassOutput => "PassOutput",
        TextureSemantics::PassFeedback => "PassFeedback",
        TextureSemantics::User => "User",
    }
}

/// Every `LIBRA_TEXTURE_<name>` sampler2D uniform this pass's *already
/// compiled* GLSL declares -- scraped from the same compiler output
/// `love-test/main.lua`'s old `findSamplers` regexed directly, just done
/// once here instead of by every Lua consumer.
fn extract_texture_uniform_names(glsl: &str) -> Vec<String> {
    const PREFIX: &str = "LIBRA_TEXTURE_";
    let mut names = Vec::new();
    for line in glsl.lines() {
        let t = line.trim();
        if !t.starts_with("uniform ") || !t.contains("sampler2D") {
            continue;
        }
        let Some(pos) = t.find(PREFIX) else { continue };
        let rest = &t[pos + PREFIX.len()..];
        let end = rest
            .find(|c: char| !(c.is_alphanumeric() || c == '_'))
            .unwrap_or(rest.len());
        let name = &rest[..end];
        if !name.is_empty() && !names.iter().any(|n: &String| n == name) {
            names.push(name.to_string());
        }
    }
    names
}

/// Classifies every declared `LIBRA_TEXTURE_<name>` sampler using the same
/// `librashader_reflect::reflect::semantics` resolution librashader itself
/// uses at runtime (`ShaderSemantics::create_pass_semantics` + the
/// `TextureSemanticMap` name-lookup fallback: explicit alias/LUT-name
/// entries first, then the built-in `Source`/`Original`/`OriginalHistoryN`/
/// `PassOutputN`/`PassFeedbackN` literal-name conventions) -- replaces the
/// Lua-side `passOutputAlias`/`originalHistory`/hardcoded
/// `"COLOR_PALETTE"`/`"BACKGROUND"` name matching: a pass reachable only
/// by its real `.slangp` alias (not a
/// literal `PassOutputN` name), or a preset with differently-named LUTs,
/// could never be resolved by that pattern matching but resolves correctly
/// here because this is the actual API meant for it, not a reimplication
/// of its naming convention.
/// `ShaderSemantics::create_pass_semantics` (the per-pass convenience API
/// this file uses instead of upstream's real `compile_preset_passes`)
/// only registers the alias of the pass being
/// compiled, not every other pass's alias -- upstream's real preset-wide
/// compile builds one shared semantics map covering every pass's alias
/// before compiling any of them (`librashader_reflect::reflect::presets::
/// compile_preset_passes`'s own `insert_pass_semantics` loop over ALL
/// passes). That gap is invisible for a preset where every cross-pass
/// texture reference uses the literal `PassOutputN` name (matched by
/// `TextureSemanticMap`'s own prefix-strip fallback regardless of this
/// map), which is all the earlier per-pass approach was ever validated
/// against -- but a real
/// preset can and does reference another pass's output purely by its own
/// `aliasN` (`ds-hybrid-scalefx.slangp`'s `scalefx-pass2.slang` samples
/// `scalefx_pass0`, pass 1's alias, with no `PassOutput1`-shaped name
/// anywhere), which the per-pass map can never resolve. Mirrors upstream's
/// own `insert_pass_semantics` (alias -> PassOutput, `<alias>Size` ->
/// PassOutput's size semantic, `<alias>Feedback`/`<alias>FeedbackSize` ->
/// PassFeedback) since that function itself isn't exported publicly.
fn insert_extra_pass_semantics(semantics: &mut ShaderSemantics, alias: &str, index: usize) {
    if alias.trim().is_empty() {
        return;
    }
    semantics.texture_semantics.insert(
        alias.into(),
        Semantic {
            semantics: TextureSemantics::PassOutput,
            index,
        },
    );
    semantics.uniform_semantics.insert(
        format!("{alias}Size").into(),
        UniformSemantic::Texture(Semantic {
            semantics: TextureSemantics::PassOutput,
            index,
        }),
    );
    semantics.texture_semantics.insert(
        format!("{alias}Feedback").into(),
        Semantic {
            semantics: TextureSemantics::PassFeedback,
            index,
        },
    );
    semantics.uniform_semantics.insert(
        format!("{alias}FeedbackSize").into(),
        UniformSemantic::Texture(Semantic {
            semantics: TextureSemantics::PassFeedback,
            index,
        }),
    );
}

fn classify_samplers(
    preset: &ShaderPreset,
    semantics: &ShaderSemantics,
    fragment: &str,
) -> Vec<SamplerOut> {
    let names = extract_texture_uniform_names(fragment);
    names
        .into_iter()
        .map(|name| match semantics.texture_semantics.texture_semantic(&name) {
            Some(sem) => {
                let user_name = if matches!(sem.semantics, TextureSemantics::User) {
                    preset.textures.get(sem.index).map(|t| t.meta.name.to_string())
                } else {
                    None
                };
                SamplerOut {
                    name,
                    semantic: texture_semantics_str(sem.semantics).to_string(),
                    index: sem.index,
                    user_name,
                }
            }
            None => SamplerOut {
                name,
                semantic: "Unknown".to_string(),
                index: 0,
                user_name: None,
            },
        })
        .collect()
}

/// Every member name a given struct (named `struct_name`) declares in this
/// pass's *already compiled* GLSL -- scraped the same way
/// `ShaderFixup.lua`'s `flattenStruct` does (`struct <name> { <type>
/// <member>; ... };`), before that struct gets flattened away into packed
/// uniforms. Includes every member of whichever struct is named: `*Size`
/// uniforms (`OutputSize`, `SourceSize`, `OriginalHistorySize1`, ...),
/// ordinary `#pragma parameter`s (`response_time`, `color_toggle`, ...), and
/// (when scanning a `LIBRA_UBO_*` struct) `MVP`/motion uniforms
/// (`Gyroscope`, `Accelerometer`, `AccelerometerRest`) alike --
/// `classify_size_uniforms` below is what tells them apart.
fn extract_struct_member_names(glsl: &str, struct_name: &str) -> Vec<String> {
    let marker = format!("struct {struct_name}");
    let Some(start) = glsl.find(marker.as_str()) else {
        return Vec::new();
    };
    let Some(open) = glsl[start..].find('{') else {
        return Vec::new();
    };
    let body_start = start + open + 1;
    let Some(close) = glsl[body_start..].find('}') else {
        return Vec::new();
    };
    let body = &glsl[body_start..body_start + close];
    body.split(';')
        .filter_map(|member| {
            let member = member.trim();
            if member.is_empty() {
                return None;
            }
            member.split_whitespace().last().map(|s| s.to_string())
        })
        .collect()
}

/// Classifies every `LIBRA_PUSH_FRAGMENT` struct member using the same
/// `librashader_reflect::reflect::semantics` name-resolution
/// `classify_samplers` above uses for texture samplers, applied to the
/// pass's own `uniform_semantics` map instead of `texture_semantics`:
/// `unique_semantic` resolves the fixed built-in names (`OutputSize`,
/// `FinalViewportSize`, `MVP`, `FrameCount`, ...), `texture_semantic`
/// resolves the `*Size` convention `TextureSemantics::size_uniform_name`
/// defines (`SourceSize`, `OriginalSize`, `OriginalHistorySizeN`,
/// `PassOutputSizeN`, `PassFeedbackSizeN`, `UserSizeN`). This replaces
/// `love-test/main.lua`'s `sizeTable()`'s own `OriginalHistorySize(%d+)`/
/// `PassOutputSize(%d+)` Lua regex -- the same class of gap the sampler-
/// wiring fix closed: a member that isn't one of those two literal name
/// shapes (a `PassFeedbackSizeN`/`UserSizeN`, which no preset under
/// `references/` happens to use but which `size_uniform_name`'s convention
/// covers just as well) could never be classified correctly by pattern
/// matching alone. Confirmed empirically (throwaway `main.rs` print block,
/// added/inspected/reverted, against the real preset): an ordinary
/// `#pragma parameter` (`response_time`, `color_toggle`, ...) is NOT an
/// unresolved name here -- `ShaderSemantics::create_pass_semantics` itself
/// registers every one of a pass's own declared parameters into
/// `uniform_semantics` as `UniqueSemantics::FloatParameter`
/// (`librashader_reflect::reflect::presets::create_pass_semantics`), so
/// `unique_semantic` resolves them too, as `kind = "unique", semantic =
/// "FloatParameter"` -- real classification, not a guess. `kind =
/// "parameter"` (semantic/index left empty) is the fallback for a name
/// that resolves to neither map, which no known preset's push struct ever
/// contains -- callers already have a separate, working mechanism for
/// actual parameter defaults (`ALL_DEFAULTS`), so this fallback only exists
/// to fail informatively rather than silently misclassify something odd as
/// a size uniform.
/// Structs classified, paired with whether to scan them from the vertex
/// (true) or fragment (false) GLSL text. `LIBRA_PUSH_FRAGMENT`/
/// `LIBRA_PUSH_VERTEX` mirror each other (same #pragma parameters, per
/// ShaderFixup.lua's own documented convention) so scanning both is
/// redundant but harmless -- names are deduped below.
/// `LIBRA_UBO_FRAGMENT`/`LIBRA_UBO_VERTEX` are new here: previously only
/// ever carried a special-cased `MVP` (substituted to `transform_projection`
/// in ShaderFixup.lua, never needing a real classified value), but a real
/// preset (pixel_transparency.slang) also declares `Gyroscope`/
/// `Accelerometer`/`AccelerometerRest` there once
/// `ShaderFeatures::SENSOR_UNIFORMS` is set -- those need real
/// classification too, the same as any other built-in.
const CLASSIFIED_STRUCTS: [(&str, bool); 4] = [
    ("LIBRA_PUSH_FRAGMENT", false),
    ("LIBRA_PUSH_VERTEX", true),
    ("LIBRA_UBO_FRAGMENT", false),
    ("LIBRA_UBO_VERTEX", true),
];

fn classify_size_uniforms(
    semantics: &ShaderSemantics,
    vertex: &str,
    fragment: &str,
) -> Vec<SizeUniformOut> {
    let mut seen = std::collections::HashSet::new();
    let mut out = Vec::new();
    for (struct_name, is_vertex) in CLASSIFIED_STRUCTS {
        let glsl = if is_vertex { vertex } else { fragment };
        for name in extract_struct_member_names(glsl, struct_name) {
            if !seen.insert(name.clone()) {
                continue; // already classified from an earlier (mirrored) struct
            }
            out.push(if let Some(sem) = semantics.uniform_semantics.unique_semantic(&name) {
                SizeUniformOut {
                    name,
                    kind: "unique".to_string(),
                    semantic: sem.semantics.as_str().to_string(),
                    index: 0,
                }
            } else if let Some(sem) = semantics.uniform_semantics.texture_semantic(&name) {
                SizeUniformOut {
                    name,
                    kind: "texture".to_string(),
                    semantic: texture_semantics_str(sem.semantics).to_string(),
                    index: sem.index,
                }
            } else {
                SizeUniformOut {
                    name,
                    kind: "parameter".to_string(),
                    semantic: String::new(),
                    index: 0,
                }
            });
        }
    }
    out
}

fn scale_type_str(t: ScaleType) -> &'static str {
    match t {
        ScaleType::Input => "source",
        ScaleType::Absolute => "absolute",
        ScaleType::Viewport => "viewport",
        ScaleType::Original => "original",
    }
}

#[derive(Serialize)]
pub struct ScalingOut {
    pub scale_type: String,
    /// "float": `factor` is a multiplier on the reference size (the normal
    /// case). "absolute": `factor` is itself the size in pixels, verbatim
    /// (only meaningful when `scale_type == "absolute"`).
    pub factor_kind: String,
    pub factor: f32,
}

fn scaling_out(s: &Scaling) -> ScalingOut {
    let (factor_kind, factor) = match s.factor {
        ScaleFactor::Float(f) => ("float", f),
        ScaleFactor::Absolute(i) => ("absolute", i as f32),
    };
    ScalingOut {
        scale_type: scale_type_str(s.scale_type).to_string(),
        factor_kind: factor_kind.to_string(),
        factor,
    }
}

/// A single `#pragma parameter` as declared in a pass's own shader source:
/// name, human-readable label, and the slider's default/min/max/step. This
/// is the real source of truth this project's Lua harnesses previously hand
/// -copied into a shared `ALL_DEFAULTS` table from reading `gb-params.inc`
/// by eye.
#[derive(Serialize)]
pub struct ParameterOut {
    pub id: String,
    pub description: String,
    pub initial: f32,
    pub minimum: f32,
    pub maximum: f32,
    pub step: f32,
}

/// A preset-level parameter override (the `.slangp` file's own `param = value`
/// lines, e.g. `gameboy-color-dot-matrix.slangp`'s `color_toggle = "1.000000"`)
/// -- applied on top of each pass's own `ParameterOut.initial` default.
#[derive(Serialize)]
pub struct ParameterOverrideOut {
    pub name: String,
    pub value: f32,
}

/// One of the preset's lookup textures (e.g. `COLOR_PALETTE`/`BACKGROUND` for
/// `gameboy-color-dot-matrix.slangp`) -- name to bind it as, the real path to
/// load, and its sampling settings. Previously hardcoded per-preset in Lua as
/// `paletteImg`/`backgroundImg`.
#[derive(Serialize)]
pub struct TextureOut {
    pub name: String,
    pub path: String,
    pub wrap_mode: String,
    pub filter_mode: String,
    pub mipmap: bool,
}

/// One `LIBRA_TEXTURE_<name>` sampler this pass's compiled GLSL declares,
/// classified via real `librashader_reflect` semantics (see
/// `classify_samplers`) instead of Lua-side name-pattern matching.
/// `semantic` is one of `"Original"`/`"Source"`/`"OriginalHistory"`/
/// `"PassOutput"`/`"PassFeedback"`/`"User"`/`"Unknown"` (the last only if
/// this pass declares a sampler no semantic could resolve at all -- a
/// genuine translation bug, not an expected case). `index` is meaningful
/// for every semantic except `Original`/`Source`/`Unknown` (always 0 there).
/// `user_name` is only set for `"User"`: the real preset texture name
/// (matches one of `TranslateResult.textures[].name`) to bind, resolved
/// from the same LUT list, not a hardcoded per-preset name.
#[derive(Serialize)]
pub struct SamplerOut {
    pub name: String,
    pub semantic: String,
    pub index: usize,
    pub user_name: Option<String>,
}

/// One `LIBRA_PUSH_FRAGMENT` struct member, classified via real
/// `librashader_reflect` semantics (see `classify_size_uniforms`) instead
/// of Lua-side `*Size` name-pattern matching. `kind` is `"unique"` (a fixed
/// built-in like `OutputSize`/`MVP`/`FrameCount` -- `semantic` names which
/// one, `index` always 0), `"texture"` (a `*Size` uniform tied to a texture
/// semantic -- `semantic` is one of `Original`/`Source`/`OriginalHistory`/
/// `PassOutput`/`PassFeedback`/`User`, `index` meaningful for every
/// semantic except `Original`/`Source`), or `"parameter"` (an ordinary
/// `#pragma parameter`, not a size uniform at all -- `semantic` empty,
/// `index` 0).
#[derive(Serialize)]
pub struct SizeUniformOut {
    pub name: String,
    pub kind: String,
    pub semantic: String,
    pub index: usize,
}

#[derive(Serialize)]
pub struct PassOutput {
    pub id: String,
    pub alias: Option<String>,
    pub vertex: String,
    pub fragment: String,
    pub filter: String,
    pub wrap_mode: String,
    pub frame_count_mod: u32,
    pub srgb_framebuffer: bool,
    pub float_framebuffer: bool,
    pub mipmap_input: bool,
    pub scale_x: ScalingOut,
    pub scale_y: ScalingOut,
    /// This pass's own `#pragma parameter` declarations (id/description/
    /// initial/min/max/step) -- every pass in the preset contributes to one
    /// flat namespace (matching how `#pragma parameter` works upstream:
    /// shared uniform names across passes are the same parameter), so a
    /// consumer merges these across all passes, then layers the preset-level
    /// `TranslateResult.parameter_overrides` on top by name.
    pub parameters: Vec<ParameterOut>,
    /// Every texture sampler this pass's fragment shader declares, real-
    /// semantics-classified. See `SamplerOut`.
    pub samplers: Vec<SamplerOut>,
    /// Every `LIBRA_PUSH_FRAGMENT` struct member this pass declares
    /// (`*Size` uniforms and `#pragma parameter`s alike), real-semantics-
    /// classified. See `SizeUniformOut`.
    pub size_uniforms: Vec<SizeUniformOut>,
}

#[derive(Serialize)]
pub struct TranslateResult {
    pub pass_count: usize,
    pub passes: Vec<PassOutput>,
    pub textures: Vec<TextureOut>,
    pub parameter_overrides: Vec<ParameterOverrideOut>,
    pub error: Option<String>,
}

/// The convert-time ESSL 100 gap: `textureSize`/`texelFetchOffset`/
/// `textureOffset` are all GLSL ES 3.00+-only -- spirv-cross refuses to
/// *emit* them for an ES 1.00 target and the whole pass fails to compile
/// (`UnsupportedSpirv("textureSize is not supported in ESSL 100.")` etc,
/// captured for real across 14 real buildbot presets by `shaderfix-repro/`).
/// Unlike every other ES-1.00 fixup this
/// project does (`ShaderFixup.lua`, all post-compile GLSL-text patches),
/// this one has to happen on the RAW `.slang` source text *before* SPIRV
/// compilation -- spirv-cross's error means no GLSL text is ever produced
/// for the pass to patch afterward. Only ever called for the ES 1.00
/// target; desktop GLSL 1.20 supports all three calls natively and is left
/// untouched. Rewrites, textually, into ES-1.00-legal equivalents:
///  - `textureSize(<Tex>, <lod>)` -> a literal `ivec2(w, h)`, for a `<Tex>`
///    that's one of this preset's own declared static textures (a LUT/
///    border PNG with fixed, load-time-known dimensions -- `lut_sizes`,
///    read directly from each PNG's IHDR chunk). `<lod>` must be a
///    non-negative integer literal (true of every real occurrence found so
///    far -- always `0`); a `<Tex>` not in `lut_sizes`, or a non-literal/
///    negative `<lod>`, is left unrewritten so it fails exactly as loudly
///    as before instead of silently guessing wrong.
///  - `texelFetchOffset(<Tex>, <coord>, <lod>, <off>)` /
///    `textureOffset(<Tex>, <uv>, <off>)` -> `texture(<Tex>, ...)` (NOT
///    `texture2D` -- the source here is still `#version 450` desktop GLSL
///    at this stage, before spirv-cross's own ES 1.00 backend does its
///    usual automatic `texture()` -> `texture2D()` downgrade during
///    emission, same as it already does for every other ordinary `texture()`
///    call in these shaders) sampling at the equivalent texel-center UV,
///    using `<Tex>`'s own `<Tex>Size` uniform's `.zw` (reciprocal size --
///    every pass-graph texture Source/PassOutputN/OriginalHistoryN/etc
///    already declares one, per the slang spec's own convention, confirmed
///    directly against `lcd-grid-v2.slang`'s existing `texelSize =
///    global.SourceSize.zw` line). The uniform's containing block instance
///    name (`params`/`global`/etc) is discovered by scanning the source's
///    own push-constant/UBO block bodies for a member named `<Tex>Size`,
///    never assumed to be one fixed block. Honest limit, not fixable
///    without a much bigger rewrite: `texture()` sampling honors the
///    sampler's configured wrap mode at out-of-range coordinates, which is
///    not necessarily identical to `texelFetch`'s implementation-defined
///    out-of-bounds behavior -- a possible edge-of-image discrepancy for
///    passes whose fetch offsets can go out of range, not measured, flagged
///    here for whoever verifies these presets' rendered output next.
fn rewrite_essl100_gaps(text: &mut String, lut_sizes: &HashMap<String, (u32, u32)>) {
    rewrite_texture_size_calls(text, lut_sizes);
    rewrite_offset_fetch_calls(text, "texelFetchOffset", true);
    rewrite_offset_fetch_calls(text, "textureOffset", false);
}

fn rewrite_texture_size_calls(text: &mut String, lut_sizes: &HashMap<String, (u32, u32)>) {
    for (start, end, args) in find_calls(text, "textureSize").into_iter().rev() {
        let (Some(tex), Some(lod)) = (args.first(), args.get(1)) else {
            continue;
        };
        let Some(&(w, h)) = lut_sizes.get(tex.trim()) else {
            continue;
        };
        let Ok(lod) = lod.trim().parse::<u32>() else {
            continue;
        };
        text.replace_range(start..end, &format!("ivec2({}, {})", w >> lod, h >> lod));
    }
}

fn rewrite_offset_fetch_calls(text: &mut String, fn_name: &str, has_lod: bool) {
    let expected_args = if has_lod { 4 } else { 3 };

    // A pass can sample another pass's PassOutput/alias purely through
    // texelFetchOffset/textureOffset with no textureSize() call of its own
    // (`ds-hybrid-scalefx.slangp`'s scalefx-pass2.slang samples its
    // `scalefx_pass0` alias this way) -- the raw shader source then never
    // declares that texture's own `<Tex>Size` uniform at all, since the
    // author never needed it directly. Ensure one exists, injected into an
    // existing uniform block, before computing any call's byte offsets
    // below (injecting text shifts every later offset, so this must fully
    // finish first, not interleave with the rewrite loop).
    let mut tex_names: Vec<String> = find_calls(text, fn_name)
        .into_iter()
        .filter(|(_, _, args)| args.len() == expected_args)
        .map(|(_, _, args)| args[0].trim().to_string())
        .collect();
    tex_names.sort();
    tex_names.dedup();
    for tex in &tex_names {
        ensure_size_uniform_declared(text, tex);
    }

    for (start, end, args) in find_calls(text, fn_name).into_iter().rev() {
        if args.len() != expected_args {
            continue;
        }
        let tex = args[0].trim();
        let Some(prefix) = find_uniform_block_instance(text, &format!("{tex}Size")) else {
            continue;
        };
        let replacement = if has_lod {
            format!(
                "texture({tex}, (vec2(({coord}) + ({off})) + vec2(0.5)) * {prefix}.{tex}Size.zw)",
                tex = tex,
                coord = args[1].trim(),
                off = args[3].trim(),
                prefix = prefix
            )
        } else {
            format!(
                "texture({tex}, ({uv}) + vec2({off}) * {prefix}.{tex}Size.zw)",
                tex = tex,
                uv = args[1].trim(),
                off = args[2].trim(),
                prefix = prefix
            )
        };
        text.replace_range(start..end, &replacement);
    }
}

/// Finds every top-level call of `name(...)` in `src` (not preceded by an
/// identifier char, so a longer name that happens to end in `name` can't
/// false-match), returning `(start_byte, end_byte_exclusive, args)` per
/// call -- `args` are the call's comma-separated argument texts, split
/// respecting nested parens/brackets so an argument like `(coord)` or
/// `ivec2(0, 0)` doesn't get sliced apart. A plain regex can't do this
/// safely since GLSL call arguments nest arbitrarily.
fn find_calls(src: &str, name: &str) -> Vec<(usize, usize, Vec<String>)> {
    let bytes = src.as_bytes();
    let pat = format!("{name}(");
    let mut out = Vec::new();
    let mut search_from = 0usize;
    while let Some(rel) = src[search_from..].find(pat.as_str()) {
        let start = search_from + rel;
        let open = start + pat.len() - 1;
        let preceded_by_ident = start > 0 && {
            let c = bytes[start - 1] as char;
            c.is_alphanumeric() || c == '_'
        };
        if preceded_by_ident {
            search_from = open + 1;
            continue;
        }
        let mut depth = 0i32;
        let mut i = open;
        let mut close = None;
        while i < bytes.len() {
            match bytes[i] {
                b'(' => depth += 1,
                b')' => {
                    depth -= 1;
                    if depth == 0 {
                        close = Some(i);
                        break;
                    }
                }
                _ => {}
            }
            i += 1;
        }
        let Some(close) = close else { break };
        let args = split_top_level_args(&src[open + 1..close]);
        out.push((start, close + 1, args));
        search_from = close + 1;
    }
    out
}

fn split_top_level_args(s: &str) -> Vec<String> {
    let mut args = Vec::new();
    let mut depth = 0i32;
    let mut cur = String::new();
    for c in s.chars() {
        match c {
            '(' | '[' => {
                depth += 1;
                cur.push(c);
            }
            ')' | ']' => {
                depth -= 1;
                cur.push(c);
            }
            ',' if depth == 0 => {
                args.push(cur.trim().to_string());
                cur = String::new();
            }
            _ => cur.push(c),
        }
    }
    if !cur.trim().is_empty() || !args.is_empty() {
        args.push(cur.trim().to_string());
    }
    args
}

/// One `[layout(...)] uniform <Block> { ... } <instance>;` declaration
/// found by `find_uniform_blocks` -- `body_start`/`body_end` bound the
/// member-declaration text between (not including) the braces.
struct UniformBlockSpan {
    instance: String,
    body_start: usize,
    body_end: usize,
}

/// Scans `src` for every `[layout(...)] uniform <Block> { ... } <instance>;`
/// declaration (push-constant or UBO alike, `params`/`global`/etc -- never
/// one fixed instance name, confirmed by both shapes existing in the real
/// corpus: `lcd-grid-v2.slang`'s `global.SourceSize` vs.
/// `scalefx-pass0.slang`'s `params.SourceSize`). Skips plain non-block
/// uniform declarations (e.g. `uniform sampler2D Source;`) by requiring a
/// `{` immediately (past whitespace) after the block-name identifier.
fn find_uniform_blocks(src: &str) -> Vec<UniformBlockSpan> {
    let bytes = src.as_bytes();
    let mut out = Vec::new();
    let mut search_from = 0usize;
    while let Some(rel) = src[search_from..].find("uniform ") {
        let kw_start = search_from + rel;
        let after_kw = kw_start + "uniform ".len();
        let rest = &src[after_kw..];
        let ident_end = rest
            .find(|c: char| !(c.is_alphanumeric() || c == '_'))
            .unwrap_or(rest.len());
        let after_ident = rest[ident_end..].trim_start();
        if !after_ident.starts_with('{') {
            search_from = after_kw;
            continue;
        }
        let open = after_kw + (rest.len() - after_ident.len());
        let mut depth = 0i32;
        let mut i = open;
        let mut close = None;
        while i < bytes.len() {
            match bytes[i] {
                b'{' => depth += 1,
                b'}' => {
                    depth -= 1;
                    if depth == 0 {
                        close = Some(i);
                        break;
                    }
                }
                _ => {}
            }
            i += 1;
        }
        let Some(close) = close else { break };
        let after = src[close + 1..].trim_start();
        let instance = after
            .split(|c: char| c == ';' || c.is_whitespace())
            .next()
            .unwrap_or("");
        if !instance.is_empty() {
            out.push(UniformBlockSpan {
                instance: instance.to_string(),
                body_start: open + 1,
                body_end: close,
            });
        }
        search_from = close + 1;
    }
    out
}

/// The accessor `<instance>` for the block (of `find_uniform_blocks`) whose
/// body declares a member named exactly `member` -- used to correctly
/// qualify a `<Tex>Size` reference once it's known to exist somewhere.
fn find_uniform_block_instance(src: &str, member: &str) -> Option<String> {
    find_uniform_blocks(src)
        .into_iter()
        .find(|b| member_declared(&src[b.body_start..b.body_end], member))
        .map(|b| b.instance)
}

/// Guarantees `<tex>Size` is declared in some uniform block of `text`,
/// injecting `vec4 <tex>Size;` into one if it isn't already there, and
/// returns that block's accessor either way. Needed for
/// `rewrite_offset_fetch_calls`: a pass can reference another pass's
/// PassOutput/alias purely through texelFetchOffset/textureOffset with no
/// textureSize() call of its own (`ds-hybrid-scalefx.slangp`'s
/// scalefx-pass2.slang samples its `scalefx_pass0` alias exactly this way),
/// so the raw shader source never declares that texture's own `*Size`
/// uniform at all -- the author never needed it directly, but our rewrite
/// does. Prefers a block that already declares some other `*Size` member
/// (matching the real convention every corpus shader already follows of
/// keeping every `*Size` uniform in one block alongside `SourceSize`/
/// `OutputSize`), falling back to the first uniform block found at all;
/// `None` only if the shader declares no uniform block whatsoever, which no
/// known real corpus shader does.
fn ensure_size_uniform_declared(text: &mut String, tex: &str) -> Option<String> {
    let member = format!("{tex}Size");
    if let Some(instance) = find_uniform_block_instance(text, &member) {
        return Some(instance);
    }
    let blocks = find_uniform_blocks(text);
    let target = blocks
        .iter()
        .find(|b| {
            text[b.body_start..b.body_end]
                .split(';')
                .any(|stmt| stmt.trim_end().ends_with("Size"))
        })
        .or_else(|| blocks.first())?;
    let instance = target.instance.clone();
    let insert_at = target.body_end;
    text.insert_str(insert_at, &format!("\tvec4 {member};\n"));
    Some(instance)
}

fn member_declared(body: &str, member: &str) -> bool {
    body.split(';').any(|stmt| {
        stmt.split_whitespace()
            .last()
            .map(|last| last == member)
            .unwrap_or(false)
    })
}

/// Reads a PNG's real pixel width/height straight from its IHDR chunk
/// (bytes 16..20 = width, 20..24 = height, big-endian u32, always the
/// first chunk right after the 8-byte signature per the PNG spec) -- no
/// image-decoding crate needed for just the header, consistent with this
/// project's preference for minimal dependencies. `None` on any read/parse
/// failure; `rewrite_texture_size_calls` treats a missing entry as "leave
/// unrewritten," so this fails the same loud, pre-existing way rather than
/// silently.
fn png_dimensions(path: &Path) -> Option<(u32, u32)> {
    let bytes = std::fs::read(path).ok()?;
    if bytes.len() < 24 || &bytes[0..8] != b"\x89PNG\r\n\x1a\n" || &bytes[12..16] != b"IHDR" {
        return None;
    }
    let w = u32::from_be_bytes(bytes[16..20].try_into().ok()?);
    let h = u32::from_be_bytes(bytes[20..24].try_into().ok()?);
    Some((w, h))
}

pub fn compile_pass_glsl(
    source: &ShaderSource,
    version: GlslVersion,
) -> Result<(String, String), Box<dyn std::error::Error>> {
    let compiled = Glslang::compile(source)?;
    let mut reflect = GLSL::from_compilation(compiled)?;
    let semantics = ShaderSemantics {
        uniform_semantics: Default::default(),
        texture_semantics: Default::default(),
    };
    // Best-effort, matching main.rs: don't fail the whole pass if reflect()
    // can't resolve semantics we never populated.
    let _ = reflect.reflect(0, &semantics);
    let output = reflect.compile(version)?;
    Ok((output.vertex, output.fragment))
}

/// Parses a `.slangp` preset and compiles every pass to GLSL text at the
/// requested dialect. No fixup (precision header, struct flattening,
/// main()->effect() rewrite) happens here -- that stays a Lua-side stage,
/// run against the returned GLSL text.
pub fn translate_preset(preset_path: &Path, version: GlslVersion) -> TranslateResult {
    // SENSOR_UNIFORMS only defines `_HAS_SENSOR_UNIFORMS` in preprocessing so
    // a preset's own `#ifdef` guard (e.g. pixel_transparency.slang's
    // Gyroscope/Accelerometer/AccelerometerRest block) compiles in -- the
    // resulting uniforms are then already classified generically by
    // classify_size_uniforms below via the real `unique_semantic` lookup,
    // same as every other built-in (OutputSize, MVP, FrameCount, ...), no
    // further special-casing needed here.
    let preset = match ShaderPreset::try_parse(preset_path, ShaderFeatures::SENSOR_UNIFORMS) {
        Ok(p) => p,
        Err(e) => {
            return TranslateResult {
                pass_count: 0,
                passes: Vec::new(),
                textures: Vec::new(),
                parameter_overrides: Vec::new(),
                error: Some(format!("preset parse failed: {e}")),
            };
        }
    };

    let textures = preset
        .textures
        .iter()
        .map(|t| TextureOut {
            name: t.meta.name.to_string(),
            path: t.path.to_string_lossy().into_owned(),
            wrap_mode: wrap_str(t.meta.wrap_mode).to_string(),
            filter_mode: filter_str(t.meta.filter_mode).to_string(),
            mipmap: t.meta.mipmap,
        })
        .collect();

    let parameter_overrides = preset
        .parameters
        .iter()
        .map(|p| ParameterOverrideOut {
            name: p.name.to_string(),
            value: p.value,
        })
        .collect();

    // Only needed for `rewrite_essl100_gaps`'s `textureSize()` case --
    // real load-time dimensions for this preset's own declared static
    // textures (LUTs, borders), read once, reused for every pass.
    let lut_sizes: HashMap<String, (u32, u32)> = preset
        .textures
        .iter()
        .filter_map(|t| png_dimensions(&t.path).map(|dim| (t.meta.name.to_string(), dim)))
        .collect();

    let mut passes = Vec::new();
    for (pass_index, pass) in preset.passes.iter().enumerate() {
        let mut source = match ShaderSource::load(&pass.path, preset.features) {
            Ok(s) => s,
            Err(e) => {
                return TranslateResult {
                    pass_count: preset.pass_count as usize,
                    passes,
                    textures,
                    parameter_overrides,
                    error: Some(format!(
                        "pass {} source load failed: {e}",
                        pass.meta.id
                    )),
                };
            }
        };
        // ES 1.00 can't emit textureSize/texelFetchOffset/
        // textureOffset at all (spirv-cross errors before any GLSL text
        // exists to patch post-compile) -- rewrite the raw source first.
        // Desktop GLSL 1.20 supports all three natively; left untouched.
        if matches!(version, GlslVersion::Glsl100Es) {
            rewrite_essl100_gaps(&mut source.vertex, &lut_sizes);
            rewrite_essl100_gaps(&mut source.fragment, &lut_sizes);
        }
        let mut parameters: Vec<ParameterOut> = source
            .parameters
            .values()
            .map(|p| ParameterOut {
                id: p.id.to_string(),
                description: p.description.clone(),
                initial: p.initial,
                minimum: p.minimum,
                maximum: p.maximum,
                step: p.step,
            })
            .collect();
        // FastHashMap iteration order isn't stable -- sort so the JSON (and
        // anything downstream that diffs it) doesn't churn run to run.
        parameters.sort_by(|a, b| a.id.cmp(&b.id));

        match compile_pass_glsl(&source, version) {
            Ok((vertex, fragment)) => {
                let mut semantics = match ShaderSemantics::create_pass_semantics::<
                    Box<dyn std::error::Error>,
                >(&preset, pass_index)
                {
                    Ok(s) => s,
                    Err(e) => {
                        return TranslateResult {
                            pass_count: preset.pass_count as usize,
                            passes,
                            textures,
                            parameter_overrides,
                            error: Some(format!(
                                "pass {} semantics failed: {e}",
                                pass.meta.id
                            )),
                        };
                    }
                };
                // See insert_extra_pass_semantics: create_pass_semantics only
                // knows this pass's own alias; a later pass can still sample
                // an earlier pass's output purely by that earlier pass's own
                // alias, which needs registering here too.
                for (other_index, other_pass) in preset.passes.iter().enumerate() {
                    if other_index == pass_index {
                        continue;
                    }
                    if let Some(alias) = other_pass.meta.alias.as_ref() {
                        insert_extra_pass_semantics(&mut semantics, alias, other_index);
                    }
                }
                let samplers = classify_samplers(&preset, &semantics, &fragment);
                let size_uniforms = classify_size_uniforms(&semantics, &vertex, &fragment);
                passes.push(PassOutput {
                    id: pass.meta.id.to_string(),
                    alias: pass.meta.alias.as_ref().map(|a| a.to_string()),
                    vertex,
                    fragment,
                    filter: filter_str(pass.meta.filter).to_string(),
                    wrap_mode: wrap_str(pass.meta.wrap_mode).to_string(),
                    frame_count_mod: pass.meta.frame_count_mod,
                    srgb_framebuffer: pass.meta.srgb_framebuffer,
                    float_framebuffer: pass.meta.float_framebuffer,
                    mipmap_input: pass.meta.mipmap_input,
                    scale_x: scaling_out(&pass.meta.scaling.x),
                    scale_y: scaling_out(&pass.meta.scaling.y),
                    parameters,
                    samplers,
                    size_uniforms,
                })
            }
            Err(e) => {
                return TranslateResult {
                    pass_count: preset.pass_count as usize,
                    passes,
                    textures,
                    parameter_overrides,
                    error: Some(format!("pass {} compile failed: {e}", pass.meta.id)),
                };
            }
        }
    }

    TranslateResult {
        pass_count: preset.pass_count as usize,
        passes,
        textures,
        parameter_overrides,
        error: None,
    }
}

/// `es != 0` targets GLSL ES 1.00 (mobile/LÖVE's ES dialect); `es == 0`
/// targets GLSL 1.20 (LÖVE's desktop dialect). Returns a JSON-encoded
/// `TranslateResult`, always -- even the error case is valid JSON with an
/// `error` string and empty `passes`, so a caller never has to distinguish
/// "call failed" from "call succeeded but returned an error" at the ABI
/// boundary, only by reading the JSON.
///
/// Ownership: the returned pointer is heap-allocated by Rust and must be
/// freed with `librashader_free_string`, never with the caller's own
/// allocator.
#[unsafe(no_mangle)]
pub extern "C" fn librashader_translate_preset(preset_path: *const c_char, es: i32) -> *mut c_char {
    let path_str = unsafe {
        if preset_path.is_null() {
            return CString::new("{\"error\":\"null preset_path\",\"pass_count\":0,\"passes\":[],\"textures\":[],\"parameter_overrides\":[]}")
                .unwrap()
                .into_raw();
        }
        CStr::from_ptr(preset_path).to_string_lossy().into_owned()
    };
    let version = if es != 0 {
        GlslVersion::Glsl100Es
    } else {
        GlslVersion::Glsl120
    };
    let result = translate_preset(Path::new(&path_str), version);
    let json = serde_json::to_string(&result).unwrap_or_else(|e| {
        format!("{{\"error\":\"serialize failed: {e}\",\"pass_count\":0,\"passes\":[],\"textures\":[],\"parameter_overrides\":[]}}")
    });
    CString::new(json)
        .unwrap_or_else(|_| {
            CString::new("{\"error\":\"nul byte in translated output\",\"pass_count\":0,\"passes\":[],\"textures\":[],\"parameter_overrides\":[]}")
                .unwrap()
        })
        .into_raw()
}

/// Frees a string returned by `librashader_translate_preset`. Must be
/// called exactly once per returned pointer, from the same allocator
/// (this library) that produced it -- never `free()` the pointer directly
/// from the caller's side.
#[unsafe(no_mangle)]
pub extern "C" fn librashader_free_string(s: *mut c_char) {
    if s.is_null() {
        return;
    }
    unsafe {
        drop(CString::from_raw(s));
    }
}
