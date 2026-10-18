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

var langLoad = Data.Code.FirstOrDefault(c => c.Name.Content == "gml_GlobalScript_scr_84_lang_load");
if (langLoad != null) {
    group.QueueReplace(langLoad, @"function scr_84_lang_load()
{
    var name = ""lang_ch1_cxkcxkckx_"" + global.lang + "".json"";
    var orig_filename = working_directory + ""lang/"" + name;
    var orig_map = scr_84_load_map_json(orig_filename);

    if (is_undefined(orig_map)) {
        orig_map = scr_84_load_map_json(working_directory + ""games/lang/"" + name);
    }
    if (is_undefined(orig_map) && global.lang == ""ja"") {
        orig_map = scr_84_load_map_json(working_directory + ""games/lang/lang_ja.json"");
    }
    if (is_undefined(orig_map) && global.lang == ""ja"") {
        orig_map = scr_84_load_map_json(working_directory + ""lang/lang_ja.json"");
    }
    if (is_undefined(orig_map)) {
        orig_map = scr_84_load_map_json(working_directory + ""games/lang/lang_ch1_cxkcxkckx_en.json"");
    }
    if (is_undefined(orig_map)) {
        orig_map = ds_map_create();
    }

    var new_filename = working_directory + ""lang-new/"" + name;
    var new_map = scr_84_load_map_json(new_filename);

    if (!is_undefined(new_map)) {
        var new_date = real(ds_map_find_value(new_map, ""date""));
        var orig_date = real(ds_map_find_value(orig_map, ""date""));
        if (new_date > orig_date) {
            ds_map_destroy(orig_map);
            orig_map = new_map;
        }
    }
    ds_map_destroy(global.lang_map);
    global.lang_map = orig_map;
    return ""loaded"";
}");
    patched++;
}

var getStr = Data.Code.FirstOrDefault(c => c.Name.Content == "gml_GlobalScript_scr_84_get_lang_string");
if (getStr != null) {
    group.QueueReplace(getStr, @"function scr_84_get_lang_string(arg0)
{
    if (is_undefined(global.lang_map) || global.lang_map == -4) return string(arg0);
    var res = ds_map_find_value(global.lang_map, arg0);
    if (is_undefined(res)) return string(arg0);
    return res;
}");
    patched++;
}

group.Import();
Console.WriteLine("  [fix_language] Total patched: " + patched);