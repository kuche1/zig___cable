
//// TODO
// fix the port_as_str

const c = @cImport({
    @cInclude("stdlib.h");
    @cInclude("arpa/inet.h");
    @cInclude("miniupnpc/miniupnpc.h");
    @cInclude("miniupnpc/upnpcommands.h");
});

const std = @import("std");
const echo = std.debug.print;


const Port_opener_data = struct{
    upnp_dev: ?*c.UPNPDev,
    upnp_urls: c.UPNPUrls,
};


pub fn init(comptime port: u32) !Port_opener_data {

    var err: c_int = 0;

    //get a list of upnp devices (asks on the broadcast address and returns the responses)
    const upnp_dev: ?*c.UPNPDev = c.upnpDiscover(
        1_000, // timeout in milliseconds
        null, // multicast address, default = "239.255.255.250"
        null, // minissdpd socket, default = "/var/run/minissdpd.sock"
        0, // source port, default = 1900
        0, // 0 = IPv4, 1 = IPv6
        50, // ttl
        &err, // error output
    );
    errdefer c.freeUPNPDevlist(upnp_dev);

    if(upnp_dev == null or err != 0) return error.couldnt_discover_upnp_device;


    var zig_lan_address: [c.INET6_ADDRSTRLEN]u8 = undefined;
    const lan_address: [*c]u8 = &zig_lan_address;
    var upnp_urls: c.UPNPUrls = undefined;
    var upnp_data: c.IGDdatas = undefined;
    const status: c_int = c.UPNP_GetValidIGD(
        upnp_dev,
        &upnp_urls,
        &upnp_data,
        lan_address,
        @sizeOf(@TypeOf(zig_lan_address)),
    );
    errdefer c.FreeUPNPUrls(&upnp_urls);

    if(status != 1) {
        // 0 = NO IGD found
        // 1 = A valid connected IGD has been found
        // 2 = A valid IGD has been found but it reported as not connected
        // 3 = an UPnP device has been found but was not recognized as an IGD
        if(status == 2){
            echo("UPnP: ignoring error...\n", .{});
        }else{
            return error.no_valid_internet_gateway_device_could_be_connected_to;
        }
    }


    var zig_wan_address: [c.INET6_ADDRSTRLEN]u8 = undefined;
    const wan_address: [*c] u8 = &zig_wan_address;
    const servicetype: [*c]const u8 = &upnp_data.first.servicetype;
    if(c.UPNP_GetExternalIPAddress(upnp_urls.controlURL, servicetype, wan_address) != 0){
        return error.cant_get_external_ip;
    }else{
        echo("UPnP: external ip: {s}\n", .{wan_address});
    }


    const port_as_str = blk: {

        var port_as_int = port;

        const size = 16;
        var port_as_str: [size]u8 = undefined;

        var ind: u9 = 0;
        while(port_as_int > 0):(ind += 1){
            if(ind >= size) {
                //@compileError("port too high, use a lower port");
                return error.port_too_high;
            }
            port_as_str[ind] = @intCast(@TypeOf(port_as_str[0]), port_as_int % 10) + '0';
            port_as_int /= 10;
        }
        port_as_str[ind] = 0;

        ind -= 1;
        var ind2: u9 = 0;
        while(ind2 < ind/2):(ind2 += 1){
            const tmp: u8 = port_as_str[ind];
            port_as_str[ind] = port_as_str[ind2];
            port_as_str[ind2] = tmp;
        }

        break :blk port_as_str;
    };

    // add a new TCP port mapping from WAN port 12345 to local host port 24680
    err = c.UPNP_AddPortMapping(
        upnp_urls.controlURL,
        servicetype,
        &port_as_str, // external (WAN) port requested
        &port_as_str, // internal (LAN) port to which packets will be redirected
        lan_address, // internal (LAN) address to which packets will be redirected
        "opened by port opener (lol)", // text description to indicate why or who is responsible for the port mapping
        "TCP", // protocol must be either TCP or UDP
        null, // remote (peer) host address or nullptr for no restriction
        "86400", // port map lease duration (in seconds) or zero for "as long as possible"
    );

    if(err != 0) return error.failed_to_map_ports;

    
    return Port_opener_data{.upnp_dev=upnp_dev, .upnp_urls=upnp_urls};

}


pub fn deinit(data: Port_opener_data) void {
    var upnp_urls = data.upnp_urls;
    var ptr_upnp_urls = &upnp_urls;
    defer c.freeUPNPDevlist(data.upnp_dev);
    defer c.FreeUPNPUrls(ptr_upnp_urls);
}


