// A stand-in emulator for the window checks on Windows, where an emulator has to be a program: it
// notes each start in emulator.log next to itself, then runs for the number of seconds in the file
// "seconds" next to itself (3 if there's none), as test/window/steps/session.js expects.
var dir = AppContext.BaseDirectory;
File.AppendAllText(Path.Combine(dir, "emulator.log"), "start " + string.Join(" ", args) + Environment.NewLine);
var secondsFile = Path.Combine(dir, "seconds");
var seconds = File.Exists(secondsFile) ? double.Parse(File.ReadAllText(secondsFile).Trim(), System.Globalization.CultureInfo.InvariantCulture) : 3;
Thread.Sleep(TimeSpan.FromSeconds(seconds));
