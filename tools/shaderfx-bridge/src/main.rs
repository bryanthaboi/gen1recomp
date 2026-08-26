use std::path::PathBuf;

use librashader_presets::{ShaderFeatures, ShaderPreset};
use librashader_preprocess::ShaderSource;
use librashader_reflect::back::glsl::GlslVersion;
use librashader_bridge::compile_pass_glsl;

fn count_uniform_vectors(glsl: &str) -> (usize, Vec<String>) {
    let mut total = 0usize;
    let mut lines = Vec::new();
    for line in glsl.lines() {
        let t = line.trim();
        if !t.starts_with("uniform ") {
            continue;
        }
        // crude: skip sampler uniforms, they don't cost a fragment uniform *vector* slot
        if t.contains("sampler") {
            lines.push(format!("(sampler, not counted) {t}"));
            continue;
        }
        let cost = if t.contains("mat4") {
            4
        } else if t.contains("mat3") {
            3
        } else if t.contains("mat2") {
            2
        } else {
            1 // scalar, vec2, vec3, vec4 all cost one vec4 slot each
        };
        // arrays: uniform float foo[8]; costs 8 slots
        let mut n = cost;
        if let Some(br) = t.find('[') {
            if let Some(close) = t[br..].find(']') {
                if let Ok(count) = t[br + 1..br + close].trim().parse::<usize>() {
                    n = cost * count;
                }
            }
        }
        total += n;
        lines.push(format!("({n} slot{}) {t}", if n == 1 { "" } else { "s" }));
    }
    (total, lines)
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let preset_path = PathBuf::from(
        "../references/slang-shaders-gameboy/handheld/gameboy-color-dot-matrix.slangp",
    );
    println!("=== parsing preset: {} ===", preset_path.display());
    let preset = ShaderPreset::try_parse(&preset_path, ShaderFeatures::empty())?;
    println!("pass_count = {}", preset.pass_count);
    for pass in &preset.passes {
        println!(
            "  pass {} alias={:?} -> {}",
            pass.meta.id,
            pass.meta.alias,
            pass.path.display()
        );
    }
    for tex in &preset.textures {
        println!(
            "  texture {} -> {} (linear={:?})",
            tex.meta.name,
            tex.path.display(),
            tex.meta.filter_mode
        );
    }
    println!();

    std::fs::create_dir_all("out")?;

    for pass in &preset.passes {
        let label = format!(
            "pass{}{}",
            pass.meta.id,
            pass.meta
                .alias
                .as_ref()
                .map(|a| format!("_{a}"))
                .unwrap_or_default()
        );
        println!("=== {label}: {} ===", pass.path.display());

        let source = match ShaderSource::load(&pass.path, preset.features) {
            Ok(s) => s,
            Err(e) => {
                println!("  !! ShaderSource::load failed: {e}");
                continue;
            }
        };
        println!("  parameters: {}", source.parameters.len());
        for (name, p) in &source.parameters {
            println!(
                "    {name} = {} (min {} max {} step {})",
                p.initial, p.minimum, p.maximum, p.step
            );
        }

        for (tag, version) in [("100es", GlslVersion::Glsl100Es), ("120", GlslVersion::Glsl120)] {
            match compile_pass_glsl(&source, version) {
                Ok((vert, frag)) => {
                    let (slots, lines) = count_uniform_vectors(&frag);
                    println!("  -- GLSL {tag}: fragment uniform-vector cost = {slots}");
                    for l in &lines {
                        println!("       {l}");
                    }
                    let out_path = format!("out/{label}_{tag}.frag.glsl");
                    std::fs::write(&out_path, &frag)?;
                    println!("     written to {out_path}");
                    let vert_path = format!("out/{label}_{tag}.vert.glsl");
                    std::fs::write(&vert_path, &vert)?;
                    println!("     written to {vert_path}");
                }
                Err(e) => {
                    println!("  !! GLSL {tag} compile failed: {e}");
                }
            }
        }
        println!();
    }

    Ok(())
}
