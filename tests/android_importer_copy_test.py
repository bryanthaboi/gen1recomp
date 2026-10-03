"""Run production Android picker copy helpers with javac (no Android SDK required).

The worker's stream/file implementation is extracted unchanged; only Log is stubbed.
Fixtures verify streaming publication, failure cleanup and destination allowlisting.
"""
from pathlib import Path
import argparse
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'mobile/android/love/src/main/java/org/love2d/android/GameActivity.java'


def method(text, anchor):
    start = text.index(anchor)
    brace = text.index('{', start)
    depth = 1
    end = brace + 1
    while depth:
        depth += (text[end] == '{') - (text[end] == '}')
        end += 1
    return text[start:end]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--source', type=Path, default=SOURCE)
    parser.add_argument('--javac', default='javac')
    parser.add_argument('--java', default='java')
    parser.add_argument('--work-dir', default=None)
    args = parser.parse_args()
    src = args.source.read_text()
    # Routing assertions guard against accidentally keeping importer copies on
    # the UI-thread path or signalling generic copies as required mod imports.
    assert 'if (directRequired || isImporterDestination(destName)) {' in src
    worker = src[src.index('if (directRequired ||'):src.index('if (!copyAssetFile(pickedSource')]
    assert 'new Thread(new Runnable()' in worker
    assert 'if (directRequired) {' in worker
    assert 'writeFlagFile(pickedRoot, PICK_ERROR_FILENAME, destName)' in worker
    assert 'getCanonicalFile()' in src and '!destFile.getPath().startsWith(rootPrefix)' in src
    picker = method(src, 'public static boolean showFilePicker(String destFilename, String saveDir)')
    assert picker.index('pickerTransfer.beginPicker()') < picker.index('self.pendingPickSaveDir =')
    assert 'if (!opened) pickerTransfer.finish();' in picker
    assert 'if (!pickerTransfer.claimResult())' in src
    assert 'if (!handedOff) pickerTransfer.finish();' in src
    assert 'STATE_PENDING_PICK_ACTIVE, pickerTransfer.isPicking()' in src
    assert 'pickerTransfer.restorePicker();' in src
    assert 'finally {' in worker and 'pickerTransfer.finish();' in worker
    result_source = src[src.index('if (requestCode != FILE_PICKER_REQUEST_CODE)'):]
    cancelled = method(result_source, 'if (uri == null)')
    assert 'PICK_CANCELLED_PREFIX + destName' in cancelled and 'isTelevision' not in cancelled
    helpers = '\n'.join(method(src, anchor) for anchor in (
        'private static boolean isImporterDestination',
        'private static final class PickerTransferGate',
        'private static final class PickCopyResult',
        'private static String hex(',
        'private static void writeFlagFile(',
        'private static PickCopyResult copyRequiredImport(',
    ))
    # Compile the actual asynchronous production branch, not a test rewrite of
    # its copy/publish/finally sequence. Android URI routing stays source-gated.
    helpers += '\nstatic final PickerTransferGate pickerTransfer = new PickerTransferGate();\n'
    helpers += 'static final String PICK_ERROR_FILENAME="pick_error.flag", PICK_COMPLETE_FILENAME="pick_complete.flag";\n'
    helpers += '''static void startProductionCopy(final InputStream pickedSource,
        final File destFile, final File pickedRoot, final String destName,
        final boolean directRequired) {\n'''
    helpers += method(src, 'if (directRequired || isImporterDestination(destName))')
    # The production branch hands ownership to the Activity result handler.
    helpers = helpers.replace('final boolean directRequired) {\nif',
        'final boolean directRequired) {\nboolean handedOff=false;\nif')
    helpers += '\n}\n'
    helpers += 'static File cancelRoot;\nstatic final String PICK_CANCELLED_PREFIX="cancelled:";\n'
    helpers += 'static void writeSaveDirFlag(String name,String body) { writeFlagFile(cancelRoot,name,body); }\n'
    helpers += 'static void productionCancel(String destName) { Object uri=null; try {\n'+cancelled+'\n} finally { pickerTransfer.finish(); } }\n'
    fixture = r'''
    static void check(boolean value, String label) {
        if (!value) throw new AssertionError(label);
    }
    static class Log { static void d(String tag, String message) {} }
    static void awaitReleased(String label) throws Exception {
        long until=System.nanoTime()+java.util.concurrent.TimeUnit.SECONDS.toNanos(5);
        while(!pickerTransfer.beginPicker()) {
            if(System.nanoTime()>=until) throw new AssertionError(label+" did not release gate");
            Thread.yield();
        }
        pickerTransfer.finish();
    }
    static class PausedInput extends ByteArrayInputStream {
        final java.util.concurrent.CountDownLatch entered=new java.util.concurrent.CountDownLatch(1);
        final java.util.concurrent.CountDownLatch proceed=new java.util.concurrent.CountDownLatch(1);
        PausedInput(byte[] bytes) { super(bytes); }
        public synchronized int read(byte[] b,int off,int len) {
            entered.countDown();
            try { check(proceed.await(5,java.util.concurrent.TimeUnit.SECONDS),"paused source released"); }
            catch(InterruptedException e) { throw new AssertionError(e); }
            return super.read(b,off,len);
        }
    }
    static class CheckedInput extends InputStream {
        final byte[] data; final File target; int cursor; boolean closed;
        CheckedInput(byte[] data, File target) { this.data=data; this.target=target; }
        public int read() {
            check(!target.exists(), "final basename published before source EOF");
            return cursor < data.length ? data[cursor++] & 255 : -1;
        }
        public int read(byte[] b, int offset, int count) {
            check(!target.exists(), "final basename visible during copy");
            if (cursor == data.length) return -1;
            int n=Math.min(Math.min(count, 32771), data.length-cursor);
            System.arraycopy(data,cursor,b,offset,n); cursor+=n; return n;
        }
        public void close() { closed=true; }
    }
    public static void main(String[] args) throws Exception {
        File root=new File(args[0]); root.mkdirs();
        check(isImporterDestination("picked_importer_gen5_bw.bin"),"gen5 accepted");
        check(isImporterDestination("picked_importer_test-2.bin"),"safe identifier accepted");
        for (String bad : new String[]{"picked_importer_.bin", "picked_importer_GEN5.bin",
            "../picked_importer_gen5_bw.bin", "x/picked_importer_gen5_bw.bin",
            "picked_importer_a\\b.bin", "picked_importer_gen5_bwXbin", "picked_rom.gb"})
            check(!isImporterDestination(bad),"unsafe/non-importer rejected: "+bad);
        byte[] data=new byte[3*1024*1024+17];
        for(int i=0;i<data.length;i++) data[i]=(byte)(i*31);
        File target=new File(root,"picked_importer_gen5_bw.bin");
        CheckedInput input=new CheckedInput(data,target);
        PickCopyResult ok=copyRequiredImport(input,target);
        check(ok.ok && ok.bytes==data.length,"successful stream copy size");
        check(input.closed,"successful stream closed");
        check(ok.md5.equals(hex(MessageDigest.getInstance("MD5").digest(data))),"MD5 exact");
        check(java.util.Arrays.equals(data,java.nio.file.Files.readAllBytes(target.toPath())),"bytes exact");
        check(!new File(target+".part").exists(),"success has no partial");
        byte[] old=java.nio.file.Files.readAllBytes(target.toPath());
        InputStream broken=new InputStream(){public int read() throws IOException {throw new IOException("fixture read failure");}};
        PickCopyResult fail=copyRequiredImport(broken,target);
        check(!fail.ok,"failure reported");
        check(java.util.Arrays.equals(old,java.nio.file.Files.readAllBytes(target.toPath())),"read failure preserves prior final");
        check(!new File(target+".part").exists(),"failure partial removed");
        File missing=new File(root,"missing.bin");
        check(!copyRequiredImport(new InputStream(){public int read() throws IOException {throw new IOException();}},missing).ok,"missing failure");
        check(!missing.exists() && !new File(missing+".part").exists(),"failure never publishes final");
        File blocked=new File(root,"blocked.bin"); blocked.mkdir();
        new FileOutputStream(new File(blocked,"prevent-delete")).close();
        check(!copyRequiredImport(new ByteArrayInputStream(data),blocked).ok,"publish failure reported");
        check(blocked.isDirectory() && !new File(blocked+".part").exists(),"publication failure cleanup");
        // Force the old race window: worker A owns the shared .part while B
        // requests the exact same importer destination or submits a duplicate result.
        File racing=new File(root,"picked_importer_race.bin");
        PausedInput paused=new PausedInput(data);
        check(pickerTransfer.beginPicker(),"first picker accepted");
        check(!pickerTransfer.beginPicker(),"second picker cannot replace pending metadata");
        check(pickerTransfer.claimResult(),"first result claimed");
        startProductionCopy(paused,racing,root,racing.getName(),true);
        check(paused.entered.await(5,java.util.concurrent.TimeUnit.SECONDS),"actual worker entered stream read");
        check(new File(racing+".part").exists(),"worker owns shared partial");
        check(!pickerTransfer.beginPicker(),"same importer blocked during actual transfer");
        check(!pickerTransfer.claimResult(),"duplicate result cannot launch a second worker");
        pickerTransfer.restorePicker();
        check(!pickerTransfer.beginPicker(),"activity restoration cannot unlock active worker");
        paused.proceed.countDown(); awaitReleased("successful worker");
        pickerTransfer.restorePicker();
        check(pickerTransfer.beginPicker(),"old PICKING bundle cannot re-arm after actual async completion");pickerTransfer.finish();
        check(java.util.Arrays.equals(data,java.nio.file.Files.readAllBytes(racing.toPath())),"raced destination is complete and unchanged");
        check(!new File(racing+".part").exists(),"race leaves no partial");
        String marker=new String(java.nio.file.Files.readAllBytes(new File(root,PICK_COMPLETE_FILENAME).toPath()),"UTF-8");
        check(marker.contains(racing.getName()) && marker.contains(hex(MessageDigest.getInstance("MD5").digest(data))),"gate retained through completion marker");
        check(pickerTransfer.beginPicker() && pickerTransfer.claimResult(),"new picker accepted after completion");
        startProductionCopy(new InputStream(){public int read() throws IOException {throw new IOException("worker failure");}},racing,root,racing.getName(),false);
        awaitReleased("failed worker");
        check(java.util.Arrays.equals(data,java.nio.file.Files.readAllBytes(racing.toPath())),"failed replacement preserves final");
        check(new File(root,PICK_ERROR_FILENAME).isFile(),"failure signalled before gate release");
        check(pickerTransfer.beginPicker() && pickerTransfer.claimResult(),"cancel fixture starts");
        cancelRoot=root; productionCancel(racing.getName());
        String cancel=new String(java.nio.file.Files.readAllBytes(new File(root,PICK_ERROR_FILENAME).toPath()),"UTF-8");
        check(cancel.equals("cancelled:"+racing.getName()),"all Android cancellation signals matching pending destination");
        check(pickerTransfer.beginPicker(),"cancel/start rejection releases picker"); pickerTransfer.finish();
        pickerTransfer.restorePicker();
        check(pickerTransfer.beginPicker(),"stale same-process saved picker does not re-arm completed transfer"); pickerTransfer.finish();
        PickerTransferGate freshProcess=new PickerTransferGate();freshProcess.restorePicker();
        check(freshProcess.isPicking() && freshProcess.claimResult(),"fresh-process restored pending picker accepts its result");freshProcess.finish();
        final java.util.concurrent.atomic.AtomicInteger winners=new java.util.concurrent.atomic.AtomicInteger();
        final java.util.concurrent.CountDownLatch simultaneous=new java.util.concurrent.CountDownLatch(1);
        Thread[] contenders=new Thread[16];
        for(int i=0;i<contenders.length;i++) {
            contenders[i]=new Thread(new Runnable(){public void run(){
                try {simultaneous.await();}catch(InterruptedException e){throw new AssertionError(e);}
                if(pickerTransfer.beginPicker()) winners.incrementAndGet();
            }}); contenders[i].start();
        }
        simultaneous.countDown();for(Thread contender:contenders) contender.join();
        check(winners.get()==1,"simultaneous picker requests have exactly one owner");pickerTransfer.finish();
        System.out.println("PASS Android importer copy: allowlist, async routing, atomic publication, exact bytes/MD5, failures, production-worker serialization, duplicate result/picker rejection and restoration");
    }
'''
    code='import java.io.*; import java.security.*; import java.util.*; public class PickerCopyFixture {\n'+helpers+fixture+'\n}'
    with tempfile.TemporaryDirectory(prefix='android-picker-copy-', dir=args.work_dir) as directory:
        work=Path(directory)
        (work/'PickerCopyFixture.java').write_text(code)
        subprocess.run([args.javac,'-encoding','UTF-8',str(work/'PickerCopyFixture.java')],check=True)
        subprocess.run([args.java,'-cp',str(work),'PickerCopyFixture',str(work/'fixtures')],check=True)


if __name__ == '__main__':
    main()
