// Windows command-line quoting, shared by the tool and by the window.
using System.Collections.Generic;
using System.Text;

internal static class CommandLine
{
    public static string Join(IEnumerable<string> arguments)
    {
        StringBuilder line = new StringBuilder();
        foreach (string a in arguments)
        {
            if (line.Length > 0)
            {
                line.Append(' ');
            }
            line.Append(Quote(a));
        }
        return line.ToString();
    }

    // Backslashes before quotes are doubled.
    private static string Quote(string a)
    {
        if (a.Length > 0 && a.IndexOfAny(new char[] { ' ', '\t', '"' }) < 0)
        {
            return a;
        }
        StringBuilder output = new StringBuilder("\"");
        int slashes = 0;
        foreach (char c in a)
        {
            if (c == '\\')
            {
                slashes++;
                continue;
            }
            output.Append('\\', c == '"' ? slashes * 2 + 1 : slashes);
            slashes = 0;
            output.Append(c);
        }
        output.Append('\\', slashes * 2);
        output.Append('"');
        return output.ToString();
    }
}
