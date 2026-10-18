using System;
using System.IO;
using System.Linq;
using UndertaleModLib;
using UndertaleModLib.Decompiler;
using UndertaleModLib.Compiler;

if (Data == null) { Console.WriteLine("Data is null"); return; }

var target = Data.Code.FirstOrDefault(c => c.Name.Content == "gml_Object_obj_CHAPTER_SELECT_Create_0");
if (target == null) { Console.WriteLine("Target not found"); return; }

var ctx = new GlobalDecompileContext(Data);
var gml = new Underanalyzer.Decompiler.DecompileContext(ctx, target, Data.ToolInfo.DecompilerSettings).DecompileToString().Replace("\r\n", "\n");

string needle = "case os_android:";
int idx = gml.IndexOf(needle);
if (idx < 0) { Console.WriteLine("Pattern not found"); return; }

int breakIdx = gml.IndexOf("break;", idx) + 6;
string insert = "\n                case os_ios:\n" +
"                    {\n" +
"                        var _f = file_text_open_write(\"select_chapter_\" + chapstring);\n" +
"                        file_text_close(_f);\n" +
"                        game_end();\n" +
"                        return;\n" +
"                    }";
gml = gml.Insert(breakIdx, insert);

string quitNeedle = "quit = function()";
int qIdx = gml.IndexOf(quitNeedle);
if (qIdx >= 0) {
    int qBodyStart = gml.IndexOf("{", qIdx);
    string quitBranch =
        "\n    if (os_type == os_ios)\n" +
        "    {\n" +
        "        var _f2 = file_text_open_write(\"launcher.temp\");\n" +
        "        file_text_close(_f2);\n" +
        "        game_end();\n" +
        "        return;\n" +
        "    }";
    gml = gml.Insert(qBodyStart + 1, quitBranch);
}

var group = new CodeImportGroup(Data);
group.QueueReplace(target, gml);
group.Import();
