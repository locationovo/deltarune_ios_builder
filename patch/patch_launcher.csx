using System;
using System.IO;
using System.Linq;
using UndertaleModLib;
using UndertaleModLib.Decompiler;
using UndertaleModLib.Compiler;

if (Data == null) { Console.WriteLine("Data is null"); return; }

string target = "gml_Object_obj_CHAPTER_SELECT_Create_0";
var code = Data.Code.FirstOrDefault(c => c.Name.Content == target);
if (code == null) { Console.WriteLine("Target not found: " + target); return; }

var ctx = new GlobalDecompileContext(Data);
var settings = Data.ToolInfo.DecompilerSettings;
string gml = new Underanalyzer.Decompiler.DecompileContext(ctx, code, settings).DecompileToString();
gml = gml.Replace("\r\n", "\n");

string needle = "ossafe_game_change(\"ch\" + chapstring);";
int idx = gml.IndexOf(needle);
if (idx < 0) {
    Console.WriteLine("Pattern not found");
    Console.WriteLine(gml.Substring(0, Math.Min(3000, gml.Length)));
    return;
}

int breakIdx = gml.IndexOf("break;", idx);
if (breakIdx < 0) { Console.WriteLine("break not found"); return; }
breakIdx += 6;

string insert =
    "\n            case os_ios:\n" +
    "                {\n" +
    "                    var _f = file_text_open_write(\"select_chapter_\" + chapstring);\n" +
    "                    file_text_close(_f);\n" +
    "                    game_end();\n" +
    "                    return;\n" +
    "                }";

gml = gml.Insert(breakIdx, insert);

var group = new CodeImportGroup(Data);
group.QueueReplace(code, gml);
group.Import();

Console.WriteLine("Patched successfully");
