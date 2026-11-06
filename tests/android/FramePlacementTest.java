package org.love2d.android;

public final class FramePlacementTest {
    private static void near(float actual, double expected) {
        if (Math.abs(actual - expected) > .0001) throw new AssertionError(actual + " != " + expected);
    }
    public static void main(String[] args) {
        FramePlacement p = new FramePlacement();
        p.update(640,480,240,216,FramePlacement.FIT);
        near(p.x,53); near(p.y,0); near(p.width,1600.0/3); near(p.height,480);
        p.update(640,480,240,216,FramePlacement.INTEGER);
        near(p.x,80); near(p.y,24); near(p.width,480); near(p.height,432);
        p.update(480,320,240,216,FramePlacement.INTEGER);
        near(p.x,120); near(p.y,52); near(p.width,240); near(p.height,216);
        p.update(480,320,240,216,FramePlacement.LEGACY);
        near(p.width,3200.0/9); near(p.height,320);
        int count = 0;
        for (int[] size : new int[][]{{160,100},{240,216},{480,320},{640,480},{721,649},{1024,768}}) {
            for (int mode : new int[]{FramePlacement.FIT,FramePlacement.INTEGER}) {
                p.update(size[0],size[1],240,216,mode);
                near(p.width/240,p.height/216);
                if (p.x<0 || p.y<0 || p.x+p.width>size[0]+.0001 || p.y+p.height>size[1]+.0001)
                    throw new AssertionError("contain clipped the image");
                near(p.x,Math.floor(p.x)); near(p.y,Math.floor(p.y)); count++;
            }
        }
        p.update(640,480,240,216,FramePlacement.COVER);
        near(p.width,640); near(p.height,576); near(p.x,0); near(p.y,-48);
        System.out.println("FramePlacement: " + count + " geometry cases and legacy/cover checks passed");
    }
}
