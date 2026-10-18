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
    if (is_undefined(global.lang_map) || global.lang_map == -4) return string(arg0);
    var res = ds_map_find_value(global.lang_map, arg0);
    if (is_undefined(res)) return string(arg0);
    return res;
}");

ReplaceFunction("gml_GlobalScript_scr_84_lang_load", @"function scr_84_lang_load()
{
    var name = ""lang_ch1_cxkcxkckx_"" + global.lang + "".json"";
    if (global.lang == ""ja"" && !file_exists(working_directory + ""lang/"" + name)) {
        name = ""lang_ja.json"";
    }
    var orig_filename = working_directory + ""lang/"" + name;
    var new_filename = working_directory + ""lang-new/"" + name;
    var filename = orig_filename;
    var type = ""orig"";
    var orig_map = scr_84_load_map_json(orig_filename);
    
    if (ds_map_size(orig_map) == 0) {
        orig_map = scr_84_load_map_json(""lang/"" + name);
    }
    if (ds_map_size(orig_map) == 0) {
        orig_map = scr_84_load_map_json(name);
    }
    
    if (ossafe_file_exists(new_filename))
    {
        var new_map = scr_84_load_map_json(new_filename);
        var new_date = real(ds_map_find_value(new_map, ""date""));
        var orig_date = real(ds_map_find_value(orig_map, ""date""));
        if (new_date > orig_date)
        {
            ds_map_destroy(orig_map);
            orig_map = new_map;
            filename = new_filename;
            type = ""new("" + string(new_date) + "")"";
        }
    }
    ds_map_destroy(global.lang_map);
    global.lang_map = orig_map;
    return type;
}");

var menuDraw = Data.Code.FirstOrDefault(c => c.Name.Content == "gml_Object_DEVICE_MENU_Draw_0");
if (menuDraw != null) {
    string gml = new Underanalyzer.Decompiler.DecompileContext(ctx, menuDraw, Data.ToolInfo.DecompilerSettings).DecompileToString().Replace("\r\n", "\n");
    gml = gml.Replace("LANGUAGETEXT = \"日本語\";", "LANGUAGETEXT = \"日本語\";");
    gml = gml.Replace("draw_set_font(fnt_ja_main);", "draw_set_font(fnt_main);");
    group.QueueReplace(menuDraw, gml);
    patched++;
}

group.Import();