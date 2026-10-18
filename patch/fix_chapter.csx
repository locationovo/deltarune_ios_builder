using System;
using System.IO;
using System.Linq;
using UndertaleModLib;
using UndertaleModLib.Decompiler;
using UndertaleModLib.Compiler;

if (Data == null) { return; }
GlobalDecompileContext ctx = new GlobalDecompileContext(Data);
CodeImportGroup group = new CodeImportGroup(Data);

var code1 = Data.Code.FirstOrDefault(c => c.Name.Content == "gml_GlobalScript_scr_chapterswitch");
if (code1 != null) {
    string gml1 = @"function scr_chapterswitch(arg0 = 0)
{
    if (os_type == os_ios)
    {
        var _f;
        if (arg0 == 0) { _f = file_text_open_write(""launcher.temp""); }
        else { _f = file_text_open_write(""select_chapter_"" + string(arg0)); }
        file_text_close(_f);
        game_end();
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
}";
    group.QueueReplace(code1, gml1);
}

var code2 = Data.Code.FirstOrDefault(c => c.Name.Content == "gml_Object_obj_CHAPTER_SELECT_Create_0");
if (code2 != null) {
    string gml2 = new Underanalyzer.Decompiler.DecompileContext(ctx, code2, Data.ToolInfo.DecompilerSettings).DecompileToString().Replace("\r\n", "\n");
    string needle = "ossafe_game_change(\"ch\" + chapstring);";
    if (gml2.Contains(needle) && !gml2.Contains("case os_ios:")) {
        int idx = gml2.IndexOf(needle);
        int breakIdx = gml2.IndexOf("break;", idx) + 6;
        string insert = "\n            case os_ios:\n" +
            "                {\n" +
            "                    var _f = file_text_open_write(\"select_chapter_\" + chapstring);\n" +
            "                    file_text_close(_f);\n" +
            "                    game_end();\n" +
            "                    return;\n" +
            "                }";
        gml2 = gml2.Insert(breakIdx, insert);
        group.QueueReplace(code2, gml2);
    }
}

group.Import();