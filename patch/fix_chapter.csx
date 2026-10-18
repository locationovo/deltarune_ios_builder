using System;
using System.IO;
using System.Linq;
using UndertaleModLib;
using UndertaleModLib.Decompiler;
using UndertaleModLib.Compiler;

if (Data == null) { Console.WriteLine("Data is null"); return; }
var ctx = new GlobalDecompileContext(Data);
var group = new CodeImportGroup(Data);
int patched = 0;

var chapSwitch = Data.Code.FirstOrDefault(c => c.Name.Content == "gml_GlobalScript_scr_chapterswitch");
if (chapSwitch != null) {
    group.QueueReplace(chapSwitch, @"function scr_chapterswitch(arg0 = 0)
{
    global.dbg_last_op = ""Switch Ch: "" + string(arg0);
    if (os_type == os_ios) { return; }
    var parameters = get_chapter_switch_parameters();
    if (arg0 == 0) {
        if (scr_is_switch_os()) { game_change(""rom:/"", parameters); }
        else {
            switch (os_type) {
                case os_windows: game_change(""/../"", ""-game data.win"" + parameters); break;
                case os_ps4: game_change("""", ""-game /app0/games/game.win"" + parameters); break;
                case os_ps5: game_change("""", ""-game /app0/games/game.win"" + parameters); break;
                case os_macosx: game_change("".."", parameters); break;
            }
        }
    } else {
        var chapstring = string(arg0);
        if (scr_is_switch_os()) { game_change(""rom:/chapter"" + chapstring + ""_switch/"", parameters); }
        else {
            switch (os_type) {
                case os_windows: game_change(""/../chapter"" + chapstring + ""_windows"", ""-game data.win"" + parameters); break;
                case os_ps4: game_change("""", ""-game /app0/games/chapter"" + chapstring + ""_ps4/game.win"" + parameters); break;
                case os_ps5: game_change("""", ""-game /app0/games/chapter"" + chapstring + ""_ps5/game.win"" + parameters); break;
                case os_macosx: game_change(""../chapter"" + chapstring + ""_mac"", parameters); break;
            }
        }
    }
}");
    patched++;
}

var contAlarm = Data.Code.FirstOrDefault(c => c.Name.Content == "gml_Object_obj_chapter_continue_Alarm_0");
if (contAlarm != null) {
    group.QueueReplace(contAlarm, @"if (choice_index == 0)
{
    var next_chapter = global.chapter + 1;
    if (os_type == os_ios)
    {
        var _f = file_text_open_write(""select_chapter_"" + string(next_chapter));
        file_text_close(_f);
        game_end();
        return;
    }
    if (global.is_console)
    {
        var _loading = instance_create(0, 0, obj_screen_loading);
        _loading.show_loading_screen(next_chapter, scr_chapterswitch);
        _loading.depth = -1000;
    }
    else
    {
        scr_chapterswitch(next_chapter);
    }
}
if (choice_index == 1)
{
    game_restart_true();
}");
    patched++;
}

var menuAlarm = Data.Code.FirstOrDefault(c => c.Name.Content == "gml_Object_DEVICE_MENU_Alarm_0");
if (menuAlarm != null) {
    group.QueueReplace(menuAlarm, @"var _target_chapter = 0;
if (os_type == os_ios)
{
    var _f = file_text_open_write(""launcher.temp"");
    file_text_close(_f);
    game_end();
    exit;
}
if (global.is_console)
{
    var _loading = instance_create(0, 0, obj_screen_loading);
    _loading.show_loading_screen(_target_chapter, scr_chapterswitch);
    _loading.depth = -1000;
}
else
{
    scr_chapterswitch(_target_chapter);
}");
    patched++;
}

group.Import();
Console.WriteLine("  [fix_chapter] Total patched: " + patched);