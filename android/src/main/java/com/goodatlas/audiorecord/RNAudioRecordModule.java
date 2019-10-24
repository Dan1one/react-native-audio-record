package com.goodatlas.audiorecord;

import android.media.AudioFormat;
import android.media.AudioRecord;
import android.media.AudioTimestamp;
import android.media.MediaRecorder.AudioSource;
import android.net.Uri;
import android.support.v4.util.CircularArray;
import android.util.Base64;
import android.util.Log;

import com.facebook.react.bridge.Promise;
import com.facebook.react.bridge.ReactApplicationContext;
import com.facebook.react.bridge.ReactContextBaseJavaModule;
import com.facebook.react.bridge.ReactMethod;
import com.facebook.react.bridge.ReadableMap;
import com.facebook.react.bridge.WritableMap;
import com.facebook.react.bridge.WritableNativeMap;
import com.facebook.react.modules.core.DeviceEventManagerModule;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.util.Map;
import java.util.Timer;

public class RNAudioRecordModule extends ReactContextBaseJavaModule {

    private final String TAG = "RNAudioRecord";
    private int bufferCount = 1;
    private final ReactApplicationContext reactContext;
    private DeviceEventManagerModule.RCTDeviceEventEmitter eventEmitter;

    private int sampleRateInHz;
    private int channelConfig;
    private int audioFormat;
    private int audioSource;

    private AudioRecord recorder;
    private int bufferSize;
    private boolean isRecording;
    private Promise completePromise;

    private String tmpFile;
    private String outFile;


    public RNAudioRecordModule(ReactApplicationContext reactContext) {
        super(reactContext);
        this.reactContext = reactContext;
    }

    @Override
    public String getName() {
        return "RNAudioRecord";
    }

    @ReactMethod
    public void init(ReadableMap options) {
        sampleRateInHz = 44100;
        if (options.hasKey("sampleRate")) {
            sampleRateInHz = options.getInt("sampleRate");
        }

        channelConfig = AudioFormat.CHANNEL_IN_MONO;
        if (options.hasKey("channels")) {
            if (options.getInt("channels") == 2) {
                channelConfig = AudioFormat.CHANNEL_IN_STEREO;
            }
        }

        audioFormat = AudioFormat.ENCODING_PCM_16BIT;
        if (options.hasKey("bitsPerSample")) {
            if (options.getInt("bitsPerSample") == 8) {
                audioFormat = AudioFormat.ENCODING_PCM_8BIT;
            }
        }

        audioSource = AudioSource.MIC;
        if (options.hasKey("audioSource")) {
            audioSource = options.getInt("audioSource");
        }

        String documentDirectoryPath = getReactApplicationContext().getFilesDir().getAbsolutePath();
        outFile = documentDirectoryPath + "/" + "audio.wav";
        tmpFile = documentDirectoryPath + "/" + "temp.pcm";
        if (options.hasKey("wavFile")) {
            String fileName = options.getString("wavFile");
            outFile = documentDirectoryPath + "/" + fileName;
        }

        isRecording = false;
        eventEmitter = reactContext.getJSModule(DeviceEventManagerModule.RCTDeviceEventEmitter.class);

        int targetRate = sampleRateInHz;
        for (int rate : new int[] {8000, 22050, 11025, 44100, 16000}) {  // add the rates you wish to check against
            int targetBufferSize = AudioRecord.getMinBufferSize(rate, channelConfig, audioFormat);
            if (targetBufferSize > 0) {
                targetRate = rate;
                bufferSize = targetBufferSize;
            }
        }
        sampleRateInHz = targetRate;

        bufferSize = AudioRecord.getMinBufferSize(sampleRateInHz, channelConfig, audioFormat);

        bufferCount = 60 * 2 * sampleRateInHz;

        recorder = new AudioRecord(audioSource, sampleRateInHz, channelConfig, audioFormat,  bufferSize * 3);

        int state = recorder.getState();
        if (AudioRecord.STATE_INITIALIZED == state)
        {
            int frameSize = recorder.getBufferSizeInFrames();

            Log.i("AUDIORECORD","Initialization Completed");

        } else {
            Log.e("AUDIORECORD","ERROR Initializing Audio Record");
        }
    }

    @ReactMethod
    public void start() {
        isRecording = true;
        recorder.startRecording();

        Thread recordingThread = new Thread(new Runnable() {
            public void run() {
                try {
                    int bytesRead;
                    int count = 0;
                    String base64Data;
                    CircularByteBuffer rb = new CircularByteBuffer(bufferCount);

//                    CircularArray circularArray = new CircularArray<byte>(3);
                    FileOutputStream os = new FileOutputStream(tmpFile);

                    AudioTimestamp startTS = new AudioTimestamp();
                    recorder.getTimestamp(startTS, AudioTimestamp.TIMEBASE_MONOTONIC);


                    byte[] buffer = new byte[bufferSize];
                    byte[] outBuffer = new byte[bufferSize];
                    AudioTimestamp duringTS = new AudioTimestamp();
                    long startTime = (long) (new Long(System.currentTimeMillis()).doubleValue());
                    int totalNumberOfBytesDiscarded = 0;
                    while (isRecording) {

                        recorder.getTimestamp(duringTS, AudioTimestamp.TIMEBASE_MONOTONIC);
                        bytesRead = recorder.read(buffer, 0, buffer.length);
                        if(rb.free() < bytesRead)
                        {
                            int numberOfBytesToRemove = bytesRead - rb.free();
                            totalNumberOfBytesDiscarded += numberOfBytesToRemove;
                            rb.get(outBuffer, 0, numberOfBytesToRemove);
                        }
                        rb.put(buffer, 0, bytesRead);
                    }
                    double now = (new Long(System.currentTimeMillis())).doubleValue();
                    long endTime = (long) now;
                    startTime = (long) Math.max(startTime, now - 60*1000);
                    recorder.stop();
                    // skip first 2 buffers to eliminate "click sound"
//                        if (bytesRead > 0 && ++count > 2) {
                    byte[] completeBuffer = new byte[rb.available()];
                    rb.get(completeBuffer, 0, rb.available());
//                    base64Data = Base64.encodeToString(completeBuffer, Base64.NO_WRAP);
//                    eventEmitter.emit("data", base64Data);
//                    os.write(completeBuffer, 0, rb.available());
                    os.write(completeBuffer);
                    os.close();
                    saveAsWav();

                    final WritableMap map = new WritableNativeMap();
                    String targetFile = Uri.fromFile(new File(outFile)).toString();

                    map.putString("filePath", targetFile);
                    map.putDouble("startTime", startTime/1000);
                    map.putDouble("endTime", endTime/1000);

                    completePromise.resolve(map);

//                        }


                } catch (Exception e) {
                    e.printStackTrace();
                }
            }
        });

        recordingThread.start();
    }

    @ReactMethod
    public void stop(final Promise promise) {


        completePromise = promise;
        isRecording = false;

//        final Timer t = new java.util.Timer();
//        t.schedule(
//                new java.util.TimerTask() {
//                    @Override
//                    public void run() {
//                        promise.resolve(map);
//                        t.cancel();
//                    }
//                },
//                10000
//        );


    }

    private void saveAsWav() {
        try {
            FileInputStream in = new FileInputStream(tmpFile);
            FileOutputStream out = new FileOutputStream(outFile);
            long totalAudioLen = in.getChannel().size();;
            long totalDataLen = totalAudioLen + 36;

            addWavHeader(out, totalAudioLen, totalDataLen);

            byte[] data = new byte[bufferSize];
            int bytesRead;
            while ((bytesRead = in.read(data)) != -1) {
                out.write(data, 0, bytesRead);
            }
            Log.d(TAG, "file path:" + outFile);
            Log.d(TAG, "file size:" + out.getChannel().size());

            in.close();
            out.close();
            deleteTempFile();
        } catch (Exception e) {
            e.printStackTrace();
        }
    }

    private void addWavHeader(FileOutputStream out, long totalAudioLen, long totalDataLen)
            throws Exception {

        long sampleRate = sampleRateInHz;
        int channels = channelConfig == AudioFormat.CHANNEL_IN_MONO ? 1 : 2;
        int bitsPerSample = audioFormat == AudioFormat.ENCODING_PCM_8BIT ? 8 : 16;
        long byteRate =  sampleRate * channels * bitsPerSample / 8;
        int blockAlign = channels * bitsPerSample / 8;

        byte[] header = new byte[44];

        header[0] = 'R';                                    // RIFF chunk
        header[1] = 'I';
        header[2] = 'F';
        header[3] = 'F';
        header[4] = (byte) (totalDataLen & 0xff);           // how big is the rest of this file
        header[5] = (byte) ((totalDataLen >> 8) & 0xff);
        header[6] = (byte) ((totalDataLen >> 16) & 0xff);
        header[7] = (byte) ((totalDataLen >> 24) & 0xff);
        header[8] = 'W';                                    // WAVE chunk
        header[9] = 'A';
        header[10] = 'V';
        header[11] = 'E';
        header[12] = 'f';                                   // 'fmt ' chunk
        header[13] = 'm';
        header[14] = 't';
        header[15] = ' ';
        header[16] = 16;                                    // 4 bytes: size of 'fmt ' chunk
        header[17] = 0;
        header[18] = 0;
        header[19] = 0;
        header[20] = 1;                                     // format = 1 for PCM
        header[21] = 0;
        header[22] = (byte) channels;                       // mono or stereo
        header[23] = 0;
        header[24] = (byte) (sampleRate & 0xff);            // samples per second
        header[25] = (byte) ((sampleRate >> 8) & 0xff);
        header[26] = (byte) ((sampleRate >> 16) & 0xff);
        header[27] = (byte) ((sampleRate >> 24) & 0xff);
        header[28] = (byte) (byteRate & 0xff);              // bytes per second
        header[29] = (byte) ((byteRate >> 8) & 0xff);
        header[30] = (byte) ((byteRate >> 16) & 0xff);
        header[31] = (byte) ((byteRate >> 24) & 0xff);
        header[32] = (byte) blockAlign;                     // bytes in one sample, for all channels
        header[33] = 0;
        header[34] = (byte) bitsPerSample;                  // bits in a sample
        header[35] = 0;
        header[36] = 'd';                                   // beginning of the data chunk
        header[37] = 'a';
        header[38] = 't';
        header[39] = 'a';
        header[40] = (byte) (totalAudioLen & 0xff);         // how big is this data chunk
        header[41] = (byte) ((totalAudioLen >> 8) & 0xff);
        header[42] = (byte) ((totalAudioLen >> 16) & 0xff);
        header[43] = (byte) ((totalAudioLen >> 24) & 0xff);

        out.write(header, 0, 44);
    }

    private void deleteTempFile() {
        File file = new File(tmpFile);
        file.delete();
    }
}
