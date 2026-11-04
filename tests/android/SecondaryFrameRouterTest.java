package org.love2d.android;

import java.nio.ByteBuffer;
import java.util.ArrayDeque;

public final class SecondaryFrameRouterTest {
    private static void check(boolean value, String message) { if (!value) throw new AssertionError(message); }
    private static class Output implements SecondaryFrameRouter.Output {
        int color, frames, value, scaling, filter; boolean visible;
        @Override public void background(int value) { color = value; }
        @Override public void frame(ByteBuffer b,int w,int h,int mode,int sampling) {
            frames++; value=b.get(0); scaling=mode; filter=sampling;
        }
        @Override public void visible(boolean value) { visible=value; }
    }
    private static class Fixture {
        final Output legacy=new Output(), gpu=new Output();
        final ArrayDeque<Runnable> tasks=new ArrayDeque<>(); int creations;
        final SecondaryFrameRouter router=new SecondaryFrameRouter(legacy,
            () -> { creations++; return gpu; }, tasks::addLast);
        Fixture() { legacy.visible=true; }
        void drain() { while(!tasks.isEmpty()) tasks.removeFirst().run(); }
    }
    private static ByteBuffer frame(int value) { return ByteBuffer.wrap(new byte[]{(byte)value,0,0,(byte)255}); }
    public static void main(String[] args) {
        Fixture f=new Fixture();
        f.router.background(0x112233);
        for(int i=0;i<100;i++) f.router.legacy(frame(i),1,1,(i&1)==1);
        check(f.creations==0 && f.tasks.isEmpty(),"legacy frames must never initialize or schedule GPU output");
        check(f.legacy.frames==100 && f.legacy.color==0x112233,"legacy frame and background preserved");
        check(f.legacy.scaling==FramePlacement.COVER,"legacy cover policy preserved");
        f.router.legacy(frame(1),1,1,false);
        check(f.legacy.scaling==FramePlacement.LEGACY,"legacy contain policy preserved");

        ByteBuffer b=frame(7);f.router.explicit(b,1,1,FramePlacement.FIT,FrameFilter.AUTO);b.put(0,(byte)99);
        check(f.creations==0 && f.tasks.size()==1,"GPU creation is deferred to the UI dispatcher");
        f.drain();check(f.creations==1 && f.gpu.value==7,"deferred frame owns its pixels");
        check(f.gpu.visible && !f.legacy.visible,"only the explicitly requested backend is visible");
        check(f.gpu.scaling==FramePlacement.FIT && f.gpu.filter==FrameFilter.AUTO,"explicit options forwarded");
        int gpuFrames=f.gpu.frames;
        f.router.explicit(frame(8),1,1,FramePlacement.INTEGER,FrameFilter.SHARP);
        check(f.tasks.isEmpty() && f.gpu.frames==gpuFrames+1,"steady GPU frames do not schedule UI work");
        f.router.legacy(frame(9),1,1,true);f.drain();
        check(f.legacy.visible && !f.gpu.visible && f.legacy.value==9,"an old caller returns to original output");
        f.router.explicit(frame(10),1,1,FramePlacement.INTEGER,FrameFilter.BILINEAR);f.drain();
        check(f.creations==1 && f.gpu.visible && f.gpu.value==10,"GPU output is reused after switching");

        Fixture latest=new Fixture();
        latest.router.explicit(frame(1),1,1,FramePlacement.FIT,FrameFilter.AUTO);
        latest.router.explicit(frame(2),1,1,FramePlacement.INTEGER,FrameFilter.NEAREST);
        check(latest.tasks.size()==1,"initial frames coalesce");latest.drain();
        check(latest.gpu.frames==1 && latest.gpu.value==2 && latest.gpu.scaling==FramePlacement.INTEGER,"latest pending frame wins");

        Fixture canceled=new Fixture();
        canceled.router.explicit(frame(1),1,1,FramePlacement.FIT,FrameFilter.AUTO);
        canceled.router.legacy(frame(2),1,1,false);canceled.drain();
        check(canceled.creations==0 && canceled.legacy.visible,"a legacy caller cancels pending GPU initialization");

        Fixture detached=new Fixture();
        detached.router.explicit(frame(1),1,1,FramePlacement.FIT,FrameFilter.AUTO);
        detached.router.close();detached.drain();
        detached.router.explicit(frame(2),1,1,FramePlacement.FIT,FrameFilter.AUTO);
        detached.router.legacy(frame(3),1,1,false);
        check(detached.creations==0 && detached.tasks.isEmpty() && detached.legacy.frames==0,"detached output rejects queued and late frames");
        System.out.println("SecondaryFrameRouter: legacy isolation, deferred ownership, switching, coalescing and detach passed");
    }
}
