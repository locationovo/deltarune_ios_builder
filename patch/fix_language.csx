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

ReplaceFunction("gml_GlobalScript_scr_84_load_map_json", @"function scr_84_load_map_json(arg0)
{
    var file_buffer = -1;
    try { file_buffer = buffer_load(arg0); } catch (_e) {}
    if (file_buffer != -1 && buffer_get_size(file_buffer) > 0)
    {
        var json = buffer_read(file_buffer, buffer_string);
        buffer_delete(file_buffer);
        var result = json_decode(json);
        if (is_undefined(result)) return ds_map_create();
        return result;
    }
    if (file_buffer != -1) buffer_delete(file_buffer);
    return ds_map_create();
}");

ReplaceFunction("gml_GlobalScript_scr_84_get_lang_string", @"function scr_84_get_lang_string(arg0)
{
    if (is_undefined(global.lang_map) || global.lang_map == -4) return string(arg0);
    var res = ds_map_find_value(global.lang_map, arg0);
    if (is_undefined(res)) return string(arg0);
    return res;
}");

ReplaceFunction("gml_GlobalScript_scr_84_init_localization", @"function scr_84_init_localization()
{
    var _locale = os_get_language();
    var _lang;
    if (scr_is_switch_os()) { _lang = substr(switch_language_get_desired_language(), 1, 2); }
    else { _lang = (substr(_locale, 1, 2) != ""ja"") ? ""en"" : ""ja""; }
    global.lang = _lang;
    if (ossafe_file_exists(""true_config.ini""))
    {
        ossafe_ini_open(""true_config.ini"");
        global.lang = ini_read_string(""LANG"", ""LANG"", _lang);
        ossafe_ini_close();
    }
    if (!variable_global_exists(""lang_loaded"")) { global.lang_loaded = """"; }
    if (!variable_global_exists(""lang""))
    {
        _locale = os_get_language();
        if (scr_is_switch_os()) { _lang = substr(switch_language_get_desired_language(), 1, 2); }
        else { _lang = (substr(_locale, 1, 2) != ""ja"") ? ""en"" : ""ja""; }
        global.lang = _lang;
    }
    if (global.lang_loaded != global.lang)
    {
        global.lang_loaded = global.lang;
        if (variable_global_exists(""lang_map""))
        {
            if (!is_undefined(global.lang_map) && global.lang_map != -4) ds_map_destroy(global.lang_map);
            if (!is_undefined(global.font_map) && global.font_map != -4) ds_map_destroy(global.font_map);
            if (!is_undefined(global.chemg_sprite_map) && global.chemg_sprite_map != -4) ds_map_destroy(global.chemg_sprite_map);
            if (!is_undefined(global.chemg_sound_map) && global.chemg_sound_map != -4) ds_map_destroy(global.chemg_sound_map);
        }
        global.lang_map = ds_map_create();
        global.font_map = ds_map_create();
        global.chemg_sprite_map = ds_map_create();
        global.chemg_sound_map = ds_map_create();
        
        scr_84_lang_load();
        if (is_undefined(global.lang_map) || global.lang_map == -4) global.lang_map = ds_map_create();
        scr_ascii_input_names();
        global.chemg_last_get_font = """";
        
        var fm = global.font_map;
        ds_map_add(fm, ""main"", fnt_main);
        ds_map_add(fm, ""mainbig"", fnt_mainbig);
        ds_map_add(fm, ""tinynoelle"", fnt_main);
        ds_map_add(fm, ""dotumche"", fnt_main);
        ds_map_add(fm, ""comicsans"", fnt_main);
        ds_map_add(fm, ""small"", fnt_main);
    }
}");

group.Import();