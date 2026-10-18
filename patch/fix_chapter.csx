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

void ReplaceFunction(string funcName, string newGml) {
    var code = Data.Code.FirstOrDefault(c => c.Name.Content == funcName);
    if (code != null) {
        group.QueueReplace(code, newGml);
        patched++;
    }
}

ReplaceFunction("gml_GlobalScript_scr_84_get_lang_string", @"function scr_84_get_lang_string(arg0)
{
    global.dbg_last_op = ""LangGet: "" + string(arg0);
    if (is_undefined(global.lang_map) || global.lang_map == -4) return string(arg0);
    var res = ds_map_find_value(global.lang_map, arg0);
    if (is_undefined(res)) return string(arg0);
    return res;
}");

ReplaceFunction("gml_GlobalScript_scr_chapterswitch", @"function scr_chapterswitch(arg0 = 0)
{
    global.dbg_last_op = ""Switch: "" + string(arg0);
    if (os_type == os_ios)
    {
        var _f;
        if (arg0 == 0) { _f = file_text_open_write(""launcher.temp""); }
        else { _f = file_text_open_write(""select_chapter_"" + string(arg0)); }
        file_text_close(_f);
        return;
    }
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

var selObj = Data.Code.FirstOrDefault(c => c.Name.Content == "gml_Object_obj_CHAPTER_SELECT_Create_0");
if (selObj != null) {
    string gml = new Underanalyzer.Decompiler.DecompileContext(ctx, selObj, Data.ToolInfo.DecompilerSettings).DecompileToString().Replace("\r\n", "\n");
    string needle = "ossafe_game_change(\"ch\" + chapstring);";
    if (gml.Contains(needle) && !gml.Contains("case os_ios:")) {
        int idx = gml.IndexOf(needle);
        int breakIdx = gml.IndexOf("break;", idx) + 6;
        string insert = "\n            case os_ios:\n" +
            "                {\n" +
            "                    var _f = file_text_open_write(\"select_chapter_\" + chapstring);\n" +
            "                    file_text_close(_f);\n" +
            "                    return;\n" +
            "                }";
        gml = gml.Insert(breakIdx, insert);
        group.QueueReplace(selObj, gml);
        patched++;
    }
}

var timeObj = Data.Code.FirstOrDefault(c => c.Name.Content == "gml_Object_obj_time_Draw_77");
if (timeObj != null) {
    string gml = new Underanalyzer.Decompiler.DecompileContext(ctx, timeObj, Data.ToolInfo.DecompilerSettings).DecompileToString().Replace("\r\n", "\n");
    string append = "\nif (variable_global_exists(\"dbg_show\") && global.dbg_show) {\n" +
        "    var w = display_get_gui_width();\n" +
        "    draw_set_color(c_black);\n" +
        "    draw_set_alpha(0.5);\n" +
        "    draw_rectangle(w - 260, 10, w - 10, 80, false);\n" +
        "    draw_set_alpha(1);\n" +
        "    draw_set_color(c_lime);\n" +
        "    draw_set_font(fnt_main);\n" +
        "    draw_set_halign(fa_right);\n" +
        "    var info = \"FPS: \" + string(fps_real) + \"\\nRoom: \" + string(room);\n" +
        "    if (variable_global_exists(\"dbg_last_op\")) info += \"\\nOp: \" + global.dbg_last_op;\n" +
        "    draw_text(w - 20, 20, info);\n" +
        "    draw_set_halign(fa_left);\n" +
        "    draw_set_color(c_white);\n" +
        "}\n";
    group.QueueReplace(timeObj, gml + append);
    patched++;
}

var initObj = Data.Code.FirstOrDefault(c => c.Name.Content == "gml_Object_obj_initializer_Create_0");
if (initObj != null) {
    string gml = new Underanalyzer.Decompiler.DecompileContext(ctx, initObj, Data.ToolInfo.DecompilerSettings).DecompileToString().Replace("\r\n", "\n");
    string append = "\nglobal.dbg_show = true;\nglobal.dbg_last_op = \"Init\";\n";
    group.QueueReplace(initObj, gml + append);
    patched++;
}

var devMenuObj = Data.Code.FirstOrDefault(c => c.Name.Content == "gml_Object_DEVICE_MENU_Step_0");
if (devMenuObj != null) {
    string gml = new Underanalyzer.Decompiler.DecompileContext(ctx, devMenuObj, Data.ToolInfo.DecompilerSettings).DecompileToString().Replace("\r\n", "\n");
    if (gml.Contains("game_end();")) {
        gml = gml.Replace("game_end();", 
            @"global.dbg_last_op = ""Quit""; file_text_close(file_text_open_write(""quit.temp""))");
        group.QueueReplace(devMenuObj, gml);
        patched++;
    }
}

group.Import();