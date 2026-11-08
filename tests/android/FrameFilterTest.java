package org.love2d.android;

import java.nio.file.Files;
import java.nio.file.Paths;
import java.nio.charset.StandardCharsets;

public final class FrameFilterTest {
    public static void main(String[] args) throws Exception {
        int checks = 0;
        for (double scale : new double[]{1,2,3,5,8}) {
            if (FrameFilter.resolve(FrameFilter.AUTO, scale, scale) != FrameFilter.NEAREST) throw new AssertionError("integer auto"); checks++;
        }
        for (double scale : new double[]{1.00001,1.25,1.5,2.222222,4.5,4.99999}) {
            if (FrameFilter.resolve(FrameFilter.AUTO, scale, scale) != FrameFilter.SHARP) throw new AssertionError("fractional auto"); checks++;
        }
        for (double scale : new double[]{.25,.75,.99999}) {
            if (FrameFilter.resolve(FrameFilter.AUTO, scale, scale) != FrameFilter.BILINEAR) throw new AssertionError("minification auto"); checks++;
        }
        for (int requested : new int[]{FrameFilter.NEAREST,FrameFilter.BILINEAR,FrameFilter.SHARP}) {
            for (double scale : new double[]{.75,1,4.5,5}) {
                if (FrameFilter.resolve(requested,scale,scale) != requested) throw new AssertionError("manual override"); checks++;
            }
        }
        if (FrameFilter.resolve(FrameFilter.AUTO,5,4.5) != FrameFilter.SHARP) throw new AssertionError("per-axis scale");
        if (args.length > 0) {
            Files.createDirectories(Paths.get(args[0]));
            Files.write(Paths.get(args[0],"vertex.glsl"),FrameFilter.VERTEX.getBytes(StandardCharsets.UTF_8));
            Files.write(Paths.get(args[0],"plain.glsl"),FrameFilter.PLAIN.getBytes(StandardCharsets.UTF_8));
            Files.write(Paths.get(args[0],"sharp.glsl"),FrameFilter.SHARP_FRAGMENT.getBytes(StandardCharsets.UTF_8));
        }
        System.out.println("FrameFilter: " + checks + " policies and shader export passed");
    }
}
