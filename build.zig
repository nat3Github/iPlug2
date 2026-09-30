const std = @import("std");

pub const Api = enum { vst3, clap, au, aax };

pub const Options = struct {
    api: Api,
    target: std.Build.ResolvedTarget,
    config_h_dir: std.Build.LazyPath,
    extra_flags: []const []const u8 = &.{},
    aax_sdk: ?std.Build.LazyPath = null,
};

pub fn build(b: *std.Build) void {
    _ = b;
}

pub fn flags(b: *std.Build, api: Api, extra: []const []const u8) []const []const u8 {
    var list: std.ArrayListUnmanaged([]const u8) = .empty;
    list.appendSlice(b.allocator, &.{
        "-DNO_IGRAPHICS",
        "-DIPLUG_NO_IGRAPHICS",
        "-DRELEASE=1",
        "-DSAMPLE_TYPE_FLOAT",
        "-fvisibility=default",
        "-fPIC",
        "-fno-sanitize=all",
        "-fno-stack-protector",
        switch (api) {
            .vst3 => "-DVST3_API",
            .clap => "-DCLAP_API",
            .au => "-DAU_API",
            .aax => "-DAAX_API",
        },
    }) catch @panic("OOM");
    if (api == .aax) list.appendSlice(b.allocator, &.{ "-DPROTOOLS", "-Wno-pragma-pack", "-Wno-incompatible-ms-struct" }) catch @panic("OOM");
    if (api == .au) list.append(b.allocator, "-Wno-deprecated-declarations") catch @panic("OOM");
    list.appendSlice(b.allocator, extra) catch @panic("OOM");
    return list.toOwnedSlice(b.allocator) catch @panic("OOM");
}

pub fn addIPlug2(dep: *std.Build.Dependency, mod: *std.Build.Module, opts: Options) void {
    const b = dep.builder;
    const os = opts.target.result.os.tag;
    const f = flags(b, opts.api, opts.extra_flags);

    mod.link_libc = true;
    mod.link_libcpp = true;
    mod.addIncludePath(opts.config_h_dir);
    for ([_][]const u8{ "IPlug", "IPlug/Extras", "IPlug/VST3", "IPlug/CLAP", "IPlug/AUv2", "IPlug/AAX", "WDL", "WDL/swell" }) |p| mod.addIncludePath(dep.path(p));
    const clap_helpers = b.dependency("clap_helpers", .{}).path("include");
    mod.addIncludePath(b.dependency("clap", .{}).path("include"));
    mod.addIncludePath(clap_helpers);
    mod.addIncludePath(clap_helpers.path(b, "clap/helpers"));

    mod.addCSourceFiles(.{
        .root = dep.path("IPlug"),
        .files = &.{ "IPlugAPIBase.cpp", "IPlugParameter.cpp", "IPlugPluginBase.cpp", "IPlugProcessor.cpp", "IPlugTimer.cpp" },
        .flags = f,
    });

    switch (opts.api) {
        .vst3 => {
            mod.addCSourceFiles(.{ .root = dep.path("IPlug/VST3"), .files = &.{ "IPlugVST3.cpp", "IPlugVST3_ProcessorBase.cpp" }, .flags = f });
            addVst3Sdk(b, mod, os);
        },
        .clap => mod.addCSourceFile(.{ .file = dep.path("IPlug/CLAP/IPlugCLAP.cpp"), .flags = f }),
        .au => {
            std.debug.assert(os == .macos);
            mod.addCSourceFile(.{ .file = dep.path("IPlug/AUv2/IPlugAU.cpp"), .flags = f });
            mod.addCSourceFile(.{ .file = dep.path("IPlug/AUv2/IPlugAU_view_factory.mm"), .flags = f });
            mod.addCSourceFile(.{ .file = dep.path("IPlug/AUv2/dfx-au-utilities.c"), .flags = f, .language = .c });
        },
        .aax => {
            const sdk = opts.aax_sdk orelse @panic("iplug2: AAX requires Options.aax_sdk");
            mod.addIncludePath(sdk.path(b, "Interfaces"));
            mod.addIncludePath(sdk.path(b, "Interfaces/ACF"));
            mod.addCSourceFiles(.{ .root = dep.path("IPlug/AAX"), .files = &.{ "IPlugAAX.cpp", "IPlugAAX_Describe.cpp", "IPlugAAX_Parameters.cpp" }, .flags = f });
            mod.addCSourceFiles(.{ .root = sdk.path(b, "Libs/AAXLibrary/Source"), .files = &aax_sources, .flags = f });
            mod.addCSourceFile(.{ .file = sdk.path(b, "Interfaces/AAX_Exports.cpp"), .flags = f });
            if (os == .macos) mod.addCSourceFile(.{ .file = sdk.path(b, "Libs/AAXLibrary/Source/AAX_CAutoreleasePool.OSX.mm"), .flags = f });
        },
    }
}

fn addVst3Sdk(b: *std.Build, mod: *std.Build.Module, os: std.Target.Os.Tag) void {
    const wf = b.addWriteFiles();
    _ = wf.addCopyDirectory(b.dependency("vst3_base", .{}).path(""), "base", .{});
    _ = wf.addCopyDirectory(b.dependency("vst3_pluginterfaces", .{}).path(""), "pluginterfaces", .{});
    _ = wf.addCopyDirectory(b.dependency("vst3_public_sdk", .{}).path(""), "public.sdk", .{});
    const root = wf.getDirectory();
    const sdk_flags: []const []const u8 = &.{ "-std=c++17", "-DRELEASE=1" };
    mod.addIncludePath(root);
    mod.addCSourceFiles(.{ .root = root, .files = &vst3_sources, .flags = sdk_flags });
    switch (os) {
        .windows => mod.addCSourceFile(.{ .file = root.path(b, "public.sdk/source/main/dllmain.cpp"), .flags = sdk_flags }),
        .macos => mod.addCSourceFile(.{ .file = root.path(b, "public.sdk/source/main/macmain.cpp"), .flags = sdk_flags }),
        else => {},
    }
}

const vst3_sources = [_][]const u8{
    "public.sdk/source/vst/vstsinglecomponenteffect.cpp",
    "public.sdk/source/vst/vstcomponentbase.cpp",
    "public.sdk/source/vst/vstbus.cpp",
    "public.sdk/source/vst/vstparameters.cpp",
    "public.sdk/source/main/pluginfactory.cpp",
    "public.sdk/source/common/commoniids.cpp",
    "public.sdk/source/common/pluginview.cpp",
    "public.sdk/source/vst/vstinitiids.cpp",
    "pluginterfaces/base/funknown.cpp",
    "pluginterfaces/base/ustring.cpp",
    "pluginterfaces/base/coreiids.cpp",
    "base/source/baseiids.cpp",
    "base/source/fobject.cpp",
    "base/source/fstring.cpp",
    "base/source/fbuffer.cpp",
    "base/source/fdebug.cpp",
    "base/source/updatehandler.cpp",
    "base/thread/source/flock.cpp",
};

const aax_sources = [_][]const u8{
    "AAX_CACFUnknown.cpp",
    "AAX_CChunkDataParser.cpp",
    "AAX_CEffectGUI.cpp",
    "AAX_CEffectParameters.cpp",
    "AAX_CHostServices.cpp",
    "AAX_CMutex.cpp",
    "AAX_CPacketDispatcher.cpp",
    "AAX_CParameter.cpp",
    "AAX_CParameterManager.cpp",
    "AAX_CString.cpp",
    "AAX_CUIDs.cpp",
    "AAX_IEffectGUI.cpp",
    "AAX_IEffectParameters.cpp",
    "AAX_VAutomationDelegate.cpp",
    "AAX_VCollection.cpp",
    "AAX_VComponentDescriptor.cpp",
    "AAX_VController.cpp",
    "AAX_VDescriptionHost.cpp",
    "AAX_VEffectDescriptor.cpp",
    "AAX_VFeatureInfo.cpp",
    "AAX_VHostServices.cpp",
    "AAX_VPageTable.cpp",
    "AAX_VPrivateDataAccess.cpp",
    "AAX_VPropertyMap.cpp",
    "AAX_VTransport.cpp",
    "AAX_VViewContainer.cpp",
    "AAX_Init.cpp",
};
