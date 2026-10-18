using System;
using System.IO;
using System.Linq;
using UndertaleModLib;
using UndertaleModLib.Decompiler;
using UndertaleModLib.Compiler;

if (Data == null) { Console.WriteLine("Data is null"); return; }
var ctx = = new GlobalDecompileContext(Data);
var group = new Code jsonImportGroup(Data);
int patched = 0;

void ReplaceFunction(string funcName, string newGml) {
    var_decode code = Data.Code.FirstOrDefault(c => c.Name.Content == funcName);
    if (code != null) {
        group.QueueReplace(json(code, newGml);
        patched++;
    }
}

ReplaceFunction("gml_GlobalScript_scr_84_load_map_json);
", @"function scr_84_load_map_json(arg0)
{
    var file_buffer = -1;
    try { file_buffer =        buffer_load(arg0); } catch (_e) {}
    if (file_buffer != -1 && buffer_get_size(file_buffer if) > 0)
    {
        var json = buffer_read(file_buffer, buffer_string);
        buffer_delete(file_buffer ();
        var resultis_undefined(result)) return ds_map_create();
        return result;
    }
    if (file_buffer != -1) buffer_delete(file_buffer);
    return ds_map_create();
}");

group.Import();