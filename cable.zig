
// zig run cable.zig --library c --library rt --library jack --library pthread --library portaudio
// zig build-exe cable.zig --library c --library rt --library jack --library pthread --library portaudio
// native x86_64-native x86_64-native-gnu

// zig build-exe cable.zig --library c --library rt --library jack --library pthread --library portaudio -target x86_64-linux

const std = @import("std");
const echo = std.debug.print;
const net = std.net;

const c = @cImport({
    @cInclude("stdlib.h");
    @cInclude("stdio.h");
    @cInclude("math.h");
    @cInclude("portaudio.h");
});











const paTestData = extern struct{
    //left_phase: f32 = 0,
    //right_phase: f32 = 0,

    left_phase: usize = 0,
    right_phase: usize = 0,
    table_size: usize = 200,
    sine: [200]f32 = undefined,
};


fn patestCallback(
                    inputBuf: ?*const c_void,
                    outputBuf: ?*c_void,
                    framesPerBuf: c_ulong,
                    timeInfo: ?*const c.PaStreamCallbackTimeInfo,
                    statusFlags: c.PaStreamCallbackFlags,
                    userData: ?*c_void,
                ) callconv(.C) c_int {

    var data = @ptrCast(*paTestData, @alignCast(@alignOf(*paTestData), userData));

    var out = @ptrCast([*c]f32, @alignCast(@alignOf(*f32), outputBuf));

    const in = @ptrCast([*c]const f32, @alignCast(@alignOf(*const f32), inputBuf));

    var i: c_ulonglong = 0;
    while(i < framesPerBuf):(i += 1){

        out[i] = in[i];

    }

    return c.paContinue;
}

fn callback_test() !void {

    {
        const err = c.Pa_Initialize();
        if(err != c.paNoError){
            echo("bruh moment: {s}\n", .{c.Pa_GetErrorText(err)});
            return error.Pa_Initialize;
        }
    }

    defer{
        const err = c.Pa_Terminate();
        if(err != c.paNoError){
            echo("error on terminate: {s}\n", .{c.Pa_GetErrorText(err)});
        }
    }

    var stream: ?*c.PaStream = undefined;
    var err: c.PaError = undefined;
    var data = paTestData{};

    {
        var i: f32 = 0;
        while(i < 200.0):(i += 1){
            data.sine[@floatToInt(usize, i)] = @floatCast(f32, c.sin( (i / 200.0) * c.M_PI * 2.0 ) );
        }
    }

    // Open an audio I/O stream.
    err = c.Pa_OpenDefaultStream( &stream,
                                1,          // 2 - stereo input ; 1 - mono ; 0 - no input channels
                                1,          // 2 - stereo output
                                c.paFloat32,  // 32 bit floating point output
                                44_100, // sample rate - 44100, 48000, ...
                                256,        // frames per buffer, i.e. the number
                                            //       of sample frames that PortAudio will
                                            //       request from the callback. Many apps
                                            //       may want to use
                                            //       paFramesPerBufferUnspecified, which
                                            //       tells PortAudio to pick the best,
                                            //       possibly changing, buffer size.
                                patestCallback, // this is your callback function
                                &data ); // This is a pointer that will be passed to
                                         //          your callback

    if(err != c.paNoError){
        echo("error on open stream: {s}\n", .{c.Pa_GetErrorText(err)});
        return error.Pa_OpenDefaultStream;
    }

    defer{
        err = c.Pa_CloseStream(stream);
        if(err != c.paNoError){
            echo("error in Pa_CloseStream\n", .{});
        }
    }

    err = c.Pa_StartStream(stream);
    if(err != c.paNoError){
        return error.Pa_StartStream;
    }

    defer{
        err = c.Pa_StopStream(stream);
        if(err != c.paNoError){
            echo("error in Pa_StopStream\n", .{});
        }
    }

    while(c.getchar() != '\n'){}

}





const SAMPLE_RATE = 48_000;
const FRAMES_PER_BUFFER = 256; // 256

pub fn main() !void {

    var err: c.PaError = undefined;

    err = c.Pa_Initialize();
    if(err != c.paNoError) return error.Pa_Initialize;
    
    defer{
        err = c.Pa_Terminate();
        if(err != c.paNoError) echo("error on terminate: {s}\n", .{c.Pa_GetErrorText(err)});
    }

    const thr1 = try std.Thread.spawn(accept_new_connection, 0);
    const thr2 = try std.Thread.spawn(establish_new_connection, 0);
    
    //try callback_test();
    
    thr1.wait();
    thr2.wait();
}








fn accept_new_connection(nothing: u32) !void {

    var host = net.StreamServer.init(.{.reuse_address=true});
    defer host.deinit();

    const addr = "0.0.0.0";
    const port = 6969;
    const parsed_addr = try net.Address.parseIp(addr, port);
    try host.listen(parsed_addr);

    const con = try host.accept();
    const adr = con.address;
    echo("connection from {}\n", .{adr});

    var stream = con.stream; // TODO change this to const

    try receive_and_play(&stream);
    
}


fn receive_and_play(net_stream: *std.net.Stream) !void {

    var err: c.PaError = undefined;
    var stream: ?*c.PaStream = undefined;

    echo("=========================== default output: {} ; count: {}\n", .{c.Pa_GetDefaultOutputDevice(), c.Pa_GetDeviceCount()});

    // Open an audio I/O stream.
    err = c.Pa_OpenDefaultStream( &stream,
                                0,          // 2 - stereo input ; 1 - mono ; 0 - no input channels
                                1,          // 2 - stereo output
                                c.paFloat32,  // 32 bit floating point output
                                SAMPLE_RATE, // sample rate - 44100, 48000, ...
                                FRAMES_PER_BUFFER,        // frames per buffer, i.e. the number
                                            //       of sample frames that PortAudio will
                                            //       request from the callback. Many apps
                                            //       may want to use
                                            //       paFramesPerBufferUnspecified, which
                                            //       tells PortAudio to pick the best,
                                            //       possibly changing, buffer size.
                                null, // this is your callback function
                                null ); // This is a pointer that will be passed to
                                         //          your callback

    if(err != c.paNoError) return error.Pa_OpenDefaultStream;

    defer{
        err = c.Pa_CloseStream(stream);
        if(err != c.paNoError) echo("error in Pa_CloseStream\n", .{});
    }

    err = c.Pa_StartStream(stream);
    if(err != c.paNoError) return error.Pa_StartStream;

    defer{
        err = c.Pa_StopStream(stream);
        if(err != c.paNoError) echo("error in Pa_StopStream\n", .{});
    }


    var buf: [FRAMES_PER_BUFFER]f32 = undefined;

    while(true){

        var data: [4]u8 = undefined;

        for(buf)|_, ind|{
            const red = net_stream.read(data[0..]) catch return error.net_stream_read;
            var fl_data = @bitCast(f32, data);
            buf[ind] = fl_data;
        }

        err = c.Pa_WriteStream(stream, &buf, FRAMES_PER_BUFFER);
        //echo("write err: {}\n", .{err});
        
    }
    
    
}
















fn establish_new_connection(nothing: u32) !void {

    const port = 6969;
    const addr = "127.0.0.1";
    const parsed_addr = try net.Address.parseIp(addr, port);
    
    var stream: std.net.Stream = undefined;
    while(true){
        stream = std.net.tcpConnectToAddress(parsed_addr) catch|err|{
            echo("unable to connect: {} ; retrying\n", .{err});
            std.time.sleep(5_000_000_000);
            continue;
        };
        break;
    }
    defer stream.close();

    try record_and_send(&stream);
    
}




fn record_and_send(net_stream: *std.net.Stream) !void {

    var err: c.PaError = undefined;
    var stream: ?*c.PaStream = undefined;

    // Open an audio I/O stream.
    err = c.Pa_OpenDefaultStream( &stream,
                                1,          // 2 - stereo input ; 1 - mono ; 0 - no input channels
                                0,          // 2 - stereo output
                                c.paFloat32,  // 32 bit floating point output
                                SAMPLE_RATE, // sample rate - 44100, 48000, ...
                                FRAMES_PER_BUFFER,        // frames per buffer, i.e. the number
                                            //       of sample frames that PortAudio will
                                            //       request from the callback. Many apps
                                            //       may want to use
                                            //       paFramesPerBufferUnspecified, which
                                            //       tells PortAudio to pick the best,
                                            //       possibly changing, buffer size.
                                null, // this is your callback function
                                null ); // This is a pointer that will be passed to
                                         //          your callback

    if(err != c.paNoError) return error.Pa_OpenDefaultStream;

    defer{
        err = c.Pa_CloseStream(stream);
        if(err != c.paNoError) echo("error in Pa_CloseStream\n", .{});
    }

    err = c.Pa_StartStream(stream);
    if(err != c.paNoError) return error.Pa_StartStream;

    defer{
        err = c.Pa_StopStream(stream);
        if(err != c.paNoError) echo("error in Pa_StopStream\n", .{});
    }


    var buf: [FRAMES_PER_BUFFER]f32 = undefined;

    while(true){

        err = c.Pa_ReadStream(stream, &buf, FRAMES_PER_BUFFER);
        //echo("read err: {}\n", .{err});

        for(buf)|data|{
            const to_send = @bitCast([4]u8, data);
            _ = net_stream.write(to_send[0..]) catch {
                return error.net_stream__write;
            };
        }
        
    }

}

