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

ReplaceFunction("gml_GlobalScript_scr_chapterswitch", @"function scr_chapterswitch(arg0 = 0)
{
    if (os_type == os_ios)
    {
        var _f;
        if (arg0 == 0) { _f = file_text_open_write(""launcher.temp""); }
        else { _f = file_text_open_write(""select_chapter_"" + string(arg0)); }
        file_text_close(_f);
        exit;
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
            "                    exit;\n" +
            "                }";
        gml = gml.Insert(breakIdx, insert);
        group.QueueReplace(selObj, gml);
        patched++;
    }
}

foreach (var code in Data.Code) {
    string gml;
    try {
        gml = new Underanalyzer.Decompiler.DecompileContext(ctx, code, Data.ToolInfo.DecompilerSettings).DecompileToString();
    } catch { continue; }
    
    if (gml.Contains("game_end();")) {
        string newGml = gml.Replace("game_end();", 
            @"{ var _q = file_text_open_write(""quit.temp""); file_text_close(_q); exit; }");
        group.QueueReplace(code, newGml);
        patched++;
    }
}

group.Import();