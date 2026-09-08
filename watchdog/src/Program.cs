using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;

namespace ImpactLED.Watchdog
{
    internal static class BootLog
    {
        public static string PathFile;

        public static void Write(string message)
        {
            try
            {
                if (string.IsNullOrEmpty(PathFile))
                {
                    string dir = AppDomain.CurrentDomain.BaseDirectory;
                    PathFile = System.IO.Path.Combine(dir, "watchdog-startup.log");
                }
                File.AppendAllText(PathFile,
                    DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + "  " + message + Environment.NewLine);
            }
            catch { }
        }
    }

    internal static class Native
    {
        public const uint WM_NULL = 0;
        public const uint SMTO_ABORTIFHUNG = 0x0002;
        public const uint SWP_NOSIZE = 0x0001;
        public const uint SWP_NOMOVE = 0x0002;
        public const uint SWP_NOACTIVATE = 0x0010;
        public const uint SWP_SHOWWINDOW = 0x0040;
        public const int SW_RESTORE = 9;
        public const int SW_SHOW = 5;
        public const int SW_MAXIMIZE = 3;
        public static readonly IntPtr HWND_TOPMOST = new IntPtr(-1);
        public static readonly IntPtr HWND_NOTOPMOST = new IntPtr(-2);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern IntPtr SendMessageTimeout(
            IntPtr hWnd, uint Msg, UIntPtr wParam, IntPtr lParam,
            uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);

        [DllImport("user32.dll")]
        public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter,
            int X, int Y, int cx, int cy, uint uFlags);

        [DllImport("user32.dll")]
        public static extern bool IsIconic(IntPtr hWnd);

        [DllImport("user32.dll")]
        public static extern bool IsWindowVisible(IntPtr hWnd);

        [DllImport("user32.dll")]
        public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

        [DllImport("user32.dll")]
        public static extern bool SetForegroundWindow(IntPtr hWnd);

        [DllImport("user32.dll")]
        public static extern IntPtr GetForegroundWindow();

        [DllImport("user32.dll")]
        public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

        [DllImport("kernel32.dll")]
        public static extern uint GetCurrentThreadId();

        [DllImport("user32.dll")]
        public static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);

        [DllImport("user32.dll")]
        public static extern bool BringWindowToTop(IntPtr hWnd);

        [DllImport("user32.dll")]
        public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

        [DllImport("user32.dll")]
        public static extern int GetWindowText(IntPtr hWnd, System.Text.StringBuilder lpString, int nMaxCount);

        [DllImport("user32.dll")]
        public static extern int GetWindowLong(IntPtr hWnd, int nIndex);

        [DllImport("user32.dll")]
        public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

        public const int GWL_EXSTYLE = -20;
        public const int WS_EX_TOOLWINDOW = 0x00000080;
        public const int WS_EX_APPWINDOW = 0x00040000;

        public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

        public struct RECT
        {
            public int Left, Top, Right, Bottom;
            public int Width { get { return Right - Left; } }
            public int Height { get { return Bottom - Top; } }
            public int Area { get { return Math.Max(0, Width) * Math.Max(0, Height); } }
        }

        public static string WindowTitle(IntPtr hwnd)
        {
            System.Text.StringBuilder sb = new System.Text.StringBuilder(512);
            GetWindowText(hwnd, sb, sb.Capacity);
            return sb.ToString();
        }

        // Largest visible top-level window that belongs to one of the player PIDs.
        public static IntPtr FindPlayerMainWindow(System.Collections.Generic.List<int> pids)
        {
            IntPtr best = IntPtr.Zero;
            int bestArea = 0;
            EnumWindows(delegate(IntPtr hwnd, IntPtr extra)
            {
                uint wpid;
                GetWindowThreadProcessId(hwnd, out wpid);
                if (!pids.Contains((int)wpid)) return true;
                if (wpid == (uint)System.Diagnostics.Process.GetCurrentProcess().Id) return true;

                int ex = GetWindowLong(hwnd, GWL_EXSTYLE);
                if ((ex & WS_EX_TOOLWINDOW) != 0) return true;

                string title = WindowTitle(hwnd);
                if (title.IndexOf("Watchdog", StringComparison.OrdinalIgnoreCase) >= 0) return true;
                if (title.IndexOf("Installer", StringComparison.OrdinalIgnoreCase) >= 0) return true;

                bool vis = IsWindowVisible(hwnd) || IsIconic(hwnd);
                if (!vis) return true;

                RECT r;
                if (!GetWindowRect(hwnd, out r)) return true;
                int area = r.Area;
                if (IsIconic(hwnd)) area = 1920 * 1080;

                if (area >= 200 * 200 && area >= bestArea)
                {
                    bestArea = area;
                    best = hwnd;
                }
                return true;
            }, IntPtr.Zero);
            return best;
        }

        public static bool IsHung(IntPtr hwnd, uint timeoutMs)
        {
            if (hwnd == IntPtr.Zero) return false;
            UIntPtr result;
            IntPtr ret = SendMessageTimeout(
                hwnd, WM_NULL, UIntPtr.Zero, IntPtr.Zero,
                SMTO_ABORTIFHUNG, timeoutMs, out result);
            return ret == IntPtr.Zero;
        }
    }

    internal sealed class Config
    {
        public string PlayerPath = @"C:\ImpactLED\CloudPlayer\ImpactLED-Cloud-Player.exe";
        public string ProcessName = "ImpactLED-Cloud-Player";
        public int PollSeconds = 8;
        public int HangTimeoutMs = 1200;
        public int HangStrikes = 3;
        public int RestartDelaySeconds = 8;
        public int MaxRestartsPerHour = 8;
        public int StartupGraceSeconds = 45;
        public bool StartIfMissing = true;
        public bool ShowToolbar = true;
        public bool AutoHide = true;
        public string Dock = "bottom";
        public bool RestoreIfMinimized = true;
        public bool KeepOnTop = true;
        public bool WatchSystemMatrix = false;
        public string SystemMatrixPath = @"C:\Program Files\Prismview\System Matrix\System Matrix.exe";

        public static Config Load(string path)
        {
            Config c = new Config();
            if (!File.Exists(path)) return c;
            foreach (string raw in File.ReadAllLines(path))
            {
                string line = raw.Trim();
                if (line.Length == 0 || line.StartsWith("#") || line.StartsWith(";")) continue;
                int eq = line.IndexOf('=');
                if (eq <= 0) continue;
                string key = line.Substring(0, eq).Trim().ToLowerInvariant();
                string val = line.Substring(eq + 1).Trim();
                switch (key)
                {
                    case "playerpath": c.PlayerPath = val; break;
                    case "processname": c.ProcessName = val; break;
                    case "pollseconds": int.TryParse(val, out c.PollSeconds); break;
                    case "hangtimeoutms": int.TryParse(val, out c.HangTimeoutMs); break;
                    case "hangstrikes": int.TryParse(val, out c.HangStrikes); break;
                    case "restartdelayseconds": int.TryParse(val, out c.RestartDelaySeconds); break;
                    case "maxrestartsperhour": int.TryParse(val, out c.MaxRestartsPerHour); break;
                    case "startupgraceseconds": int.TryParse(val, out c.StartupGraceSeconds); break;
                    case "startifmissing": bool.TryParse(val, out c.StartIfMissing); break;
                    case "showtoolbar": bool.TryParse(val, out c.ShowToolbar); break;
                    case "autohide": bool.TryParse(val, out c.AutoHide); break;
                    case "dock": c.Dock = val.ToLowerInvariant(); break;
                    case "restoreifminimized": bool.TryParse(val, out c.RestoreIfMinimized); break;
                    case "keepontop": bool.TryParse(val, out c.KeepOnTop); break;
                    case "watchsystemmatrix": bool.TryParse(val, out c.WatchSystemMatrix); break;
                    case "systemmatrixpath": c.SystemMatrixPath = val; break;
                }
            }
            return c;
        }

        public void Save(string path)
        {
            File.WriteAllLines(path, new string[] {
                "# ImpactLED Player Watchdog",
                "PlayerPath=" + PlayerPath,
                "ProcessName=" + ProcessName,
                "PollSeconds=" + PollSeconds,
                "HangTimeoutMs=" + HangTimeoutMs,
                "HangStrikes=" + HangStrikes,
                "RestartDelaySeconds=" + RestartDelaySeconds,
                "MaxRestartsPerHour=" + MaxRestartsPerHour,
                "StartupGraceSeconds=" + StartupGraceSeconds,
                "StartIfMissing=" + StartIfMissing,
                "ShowToolbar=" + ShowToolbar,
                "AutoHide=" + AutoHide,
                "Dock=" + Dock,
                "RestoreIfMinimized=" + RestoreIfMinimized,
                "KeepOnTop=" + KeepOnTop,
                "WatchSystemMatrix=" + WatchSystemMatrix,
                "SystemMatrixPath=" + SystemMatrixPath
            });
        }
    }

    internal sealed class Engine
    {
        public readonly Config Cfg;
        public bool Paused;
        public string LastStatus = "Starting";
        public string LastAction = "Loaded";
        public int? LastPid;
        public int HangCount;

        private readonly List<DateTime> _restarts = new List<DateTime>();
        private DateTime _nextAction = DateTime.MinValue;
        private readonly string _logDir;
        private string _logFile;

        public Engine(Config cfg)
        {
            Cfg = cfg;
            string installDir = Path.GetDirectoryName(cfg.PlayerPath);
            if (string.IsNullOrEmpty(installDir)) installDir = @"C:\ImpactLED\CloudPlayer";
            _logDir = Path.Combine(installDir, "watchdog-logs");
            try { Directory.CreateDirectory(_logDir); } catch { }
            RollLog();
        }

        public string LogDir { get { return _logDir; } }
        public string LogFile { get { return _logFile; } }
        public string InstallDir
        {
            get
            {
                string d = Path.GetDirectoryName(Cfg.PlayerPath);
                return string.IsNullOrEmpty(d) ? @"C:\ImpactLED\CloudPlayer" : d;
            }
        }

        private void RollLog()
        {
            _logFile = Path.Combine(_logDir, "watchdog-" + DateTime.Now.ToString("yyyy-MM-dd") + ".log");
        }

        public void Log(string level, string message)
        {
            RollLog();
            string line = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + "  [" + level.PadRight(5) + "]  " + message;
            try { File.AppendAllText(_logFile, line + Environment.NewLine); } catch { }
            BootLog.Write("[" + level + "] " + message);
        }

        private Process[] GetPlayers()
        {
            try { return Process.GetProcessesByName(Cfg.ProcessName); }
            catch { return new Process[0]; }
        }

        private static bool WindowHung(Process p, int timeoutMs)
        {
            try
            {
                IntPtr hwnd = IntPtr.Zero;
                try { hwnd = p.MainWindowHandle; } catch { }
                if (hwnd != IntPtr.Zero)
                    return Native.IsHung(hwnd, (uint)Math.Max(400, timeoutMs));
                try { if (!p.Responding) return true; } catch { }
            }
            catch { }
            return false;
        }

        private class State
        {
            public string Status;
            public string Detail;
            public Process Proc;
            public int? Pid;
        }

        private State ReadState()
        {
            Process[] procs = GetPlayers();
            if (procs == null || procs.Length == 0)
                return new State { Status = "DOWN", Detail = "Process not running" };

            Process ui = null;
            for (int i = 0; i < procs.Length; i++)
            {
                try
                {
                    if (procs[i].MainWindowHandle != IntPtr.Zero) { ui = procs[i]; break; }
                }
                catch { }
            }
            if (ui == null) ui = procs[0];

            TimeSpan age = TimeSpan.Zero;
            try { age = DateTime.Now - ui.StartTime; } catch { }
            if (age.TotalSeconds < Cfg.StartupGraceSeconds)
            {
                return new State
                {
                    Status = "STARTING",
                    Detail = "PID " + ui.Id + " starting",
                    Proc = ui,
                    Pid = ui.Id
                };
            }

            if (WindowHung(ui, Cfg.HangTimeoutMs))
            {
                return new State
                {
                    Status = "HUNG",
                    Detail = "PID " + ui.Id + " not responding",
                    Proc = ui,
                    Pid = ui.Id
                };
            }

            long mb = 0;
            try { mb = ui.WorkingSet64 / (1024 * 1024); } catch { }
            return new State
            {
                Status = "RUNNING",
                Detail = "PID " + ui.Id + "  " + mb + " MB",
                Proc = ui,
                Pid = ui.Id
            };
        }

        private bool BudgetOk()
        {
            DateTime cutoff = DateTime.Now.AddHours(-1);
            for (int i = _restarts.Count - 1; i >= 0; i--)
                if (_restarts[i] < cutoff) _restarts.RemoveAt(i);
            return _restarts.Count < Cfg.MaxRestartsPerHour;
        }

        public void StopPlayer(Process p)
        {
            if (p == null)
            {
                Process[] all = GetPlayers();
                for (int i = 0; i < all.Length; i++)
                {
                    try { all[i].Kill(); } catch { }
                }
                return;
            }
            Log("WARN", "Stopping player PID " + p.Id);
            try { p.Kill(); } catch { }
            Process[] leftover = GetPlayers();
            for (int i = 0; i < leftover.Length; i++)
            {
                try { leftover[i].Kill(); } catch { }
            }
        }

        public bool StartPlayer()
        {
            if (!File.Exists(Cfg.PlayerPath))
            {
                Log("ERROR", "Player EXE not found: " + Cfg.PlayerPath);
                LastAction = "EXE missing";
                return false;
            }
            if (!BudgetOk())
            {
                Log("ERROR", "Restart budget exhausted");
                LastAction = "Budget exhausted";
                return false;
            }
            Log("INFO", "Starting player: " + Cfg.PlayerPath);
            try
            {
                ProcessStartInfo psi = new ProcessStartInfo();
                psi.FileName = Cfg.PlayerPath;
                psi.WorkingDirectory = InstallDir;
                psi.UseShellExecute = true;
                Process.Start(psi);
                _restarts.Add(DateTime.Now);
                HangCount = 0;
                LastAction = "Restarted " + DateTime.Now.ToString("HH:mm:ss");
                _nextAction = DateTime.Now.AddSeconds(Cfg.RestartDelaySeconds);
                return true;
            }
            catch (Exception ex)
            {
                Log("ERROR", "Start failed: " + ex.Message);
                LastAction = "Start failed";
                return false;
            }
        }

        public void ManualRestart()
        {
            Log("INFO", "Manual restart requested");
            Process[] procs = GetPlayers();
            if (procs.Length > 0) StopPlayer(procs[0]);
            StartPlayer();
        }

        private DateTime _lastRaiseLog = DateTime.MinValue;

        public void EnsureVisible(Process p)
        {
            if (!Cfg.RestoreIfMinimized && !Cfg.KeepOnTop) return;

            System.Collections.Generic.List<int> pids = new System.Collections.Generic.List<int>();
            Process[] all = GetPlayers();
            string want = "";
            try { want = Path.GetFullPath(Cfg.PlayerPath).ToLowerInvariant(); } catch { want = Cfg.PlayerPath.ToLowerInvariant(); }
            for (int i = 0; i < all.Length; i++)
            {
                try
                {
                    string path = "";
                    try { path = all[i].MainModule.FileName; } catch { }
                    if (!string.IsNullOrEmpty(path) && path.ToLowerInvariant() != want)
                        continue;
                    pids.Add(all[i].Id);
                }
                catch { }
            }
            if (pids.Count == 0 && p != null) pids.Add(p.Id);

            IntPtr hwnd = Native.FindPlayerMainWindow(pids);
            if (hwnd == IntPtr.Zero) return;

            bool changed = false;
            try
            {
                if (Cfg.RestoreIfMinimized && Native.IsIconic(hwnd))
                {
                    Native.ShowWindow(hwnd, Native.SW_RESTORE);
                    changed = true;
                }

                if (Cfg.KeepOnTop)
                {
                    Native.SetWindowPos(hwnd, Native.HWND_TOPMOST, 0, 0, 0, 0,
                        Native.SWP_NOMOVE | Native.SWP_NOSIZE | Native.SWP_SHOWWINDOW);
                    Native.BringWindowToTop(hwnd);
                    Native.SetForegroundWindow(hwnd);
                    changed = true;
                }
            }
            catch (Exception ex)
            {
                Log("WARN", "EnsureVisible failed: " + ex.Message);
            }

            if (changed && DateTime.Now - _lastRaiseLog > TimeSpan.FromSeconds(30))
            {
                _lastRaiseLog = DateTime.Now;
                string title = Native.WindowTitle(hwnd);
                LastAction = "Raised player";
                Log("INFO", "Raised player hwnd=" + hwnd.ToInt64().ToString("X") + " title=" + title);
            }
        }

        public void Tick()
        {
            if (Paused)
            {
                LastStatus = "PAUSED";
                return;
            }

            State state = ReadState();
            LastStatus = state.Status;
            if (state.Pid.HasValue) LastPid = state.Pid;

            switch (state.Status)
            {
                case "RUNNING":
                case "STARTING":
                    HangCount = 0;
                    EnsureVisible(state.Proc);
                    break;
                case "HUNG":
                    HangCount++;
                    Log("WARN", "Hang strike " + HangCount + "/" + Cfg.HangStrikes + " — " + state.Detail);
                    if (HangCount >= Cfg.HangStrikes && DateTime.Now >= _nextAction)
                    {
                        StopPlayer(state.Proc);
                        _nextAction = DateTime.Now.AddSeconds(Cfg.RestartDelaySeconds);
                        StartPlayer();
                    }
                    break;
                case "DOWN":
                    if (DateTime.Now >= _nextAction)
                    {
                        Log("WARN", "Player is down — starting");
                        HangCount = 0;
                        StartPlayer();
                    }
                    break;
            }

            if (Cfg.WatchSystemMatrix)
            {
                Process[] sm = new Process[0];
                try { sm = Process.GetProcessesByName("System Matrix"); } catch { }
                if (sm.Length == 0 && File.Exists(Cfg.SystemMatrixPath))
                {
                    Log("WARN", "System Matrix not running — starting");
                    try { Process.Start(Cfg.SystemMatrixPath); } catch { }
                }
            }
        }
    }

    internal sealed class MainForm : Form
    {
        private readonly Engine _eng;
        private readonly Label _dot;
        private readonly Label _lbl;
        private readonly Button _btnRestart;
        private readonly Button _btnPause;
        private readonly Button _btnLogs;
        private readonly Button _btnPin;
        private readonly NotifyIcon _tray;
        private readonly System.Windows.Forms.Timer _pollTimer;
        private readonly System.Windows.Forms.Timer _edgeTimer;
        private bool _wantBar;
        private bool _autoHide;
        private bool _pinned;
        private DateTime _hideAt = DateTime.MaxValue;

        public MainForm(Engine eng)
        {
            _eng = eng;
            _wantBar = eng.Cfg.ShowToolbar;
            _autoHide = eng.Cfg.AutoHide;
            _pinned = !_autoHide;

            Text = "ImpactLED Player Watchdog";
            ShowInTaskbar = false;
            FormBorderStyle = FormBorderStyle.None;
            TopMost = true;
            StartPosition = FormStartPosition.Manual;
            BackColor = Color.FromArgb(15, 23, 42);
            Opacity = 0.94;
            Height = 36;
            PlaceBar();

            _dot = new Label();
            _dot.Text = "●";
            _dot.ForeColor = Color.FromArgb(59, 130, 246);
            _dot.Font = new Font("Segoe UI", 14, FontStyle.Bold);
            _dot.AutoSize = true;
            _dot.Left = 10;
            _dot.Top = 2;
            Controls.Add(_dot);

            _lbl = new Label();
            _lbl.ForeColor = Color.White;
            _lbl.Font = new Font("Segoe UI", 9.5f);
            _lbl.AutoSize = true;
            _lbl.Left = 32;
            _lbl.Top = 9;
            _lbl.Text = "ImpactLED Player Watchdog  |  starting...";
            Controls.Add(_lbl);

            int x = Width - 420;
            _btnRestart = MakeButton("Restart", x, delegate { Safe(delegate { _eng.ManualRestart(); RefreshUi(); }); });
            _btnPause = MakeButton("Pause", x + 84, delegate
            {
                _eng.Paused = !_eng.Paused;
                _eng.Log("INFO", _eng.Paused ? "Watchdog paused" : "Watchdog resumed");
                RefreshUi();
            });
            _btnLogs = MakeButton("Logs", x + 168, delegate
            {
                try
                {
                    if (File.Exists(_eng.LogFile))
                        Process.Start("notepad.exe", _eng.LogFile);
                    else
                        Process.Start("explorer.exe", _eng.LogDir);
                }
                catch { }
            });
            _btnPin = MakeButton(_pinned ? "Unpin" : "Pin", x + 252, delegate
            {
                _pinned = !_pinned;
                _autoHide = !_pinned;
                _eng.Cfg.AutoHide = _autoHide;
                _btnPin.Text = _pinned ? "Unpin" : "Pin";
                if (_pinned) ShowBar();
                else ArmHide();
            });
            MakeButton("Hide", x + 336, delegate
            {
                _wantBar = false;
                Hide();
            });

            _tray = new NotifyIcon();
            _tray.Text = "ImpactLED Player Watchdog";
            _tray.Visible = true;
            try { _tray.Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath); }
            catch { _tray.Icon = SystemIcons.Information; }

            ContextMenuStrip menu = new ContextMenuStrip();
            menu.Items.Add("Show toolbar", null, delegate { _wantBar = true; ShowBar(); });
            menu.Items.Add("Restart player now", null, delegate { _btnRestart.PerformClick(); });
            menu.Items.Add("Pause / resume", null, delegate { _btnPause.PerformClick(); });
            menu.Items.Add("Pin / unpin bar", null, delegate { _btnPin.PerformClick(); });
            menu.Items.Add("Open player folder", null, delegate
            {
                try { if (Directory.Exists(_eng.InstallDir)) Process.Start("explorer.exe", _eng.InstallDir); } catch { }
            });
            menu.Items.Add("Open log", null, delegate { _btnLogs.PerformClick(); });
            menu.Items.Add("-");
            menu.Items.Add("Exit watchdog", null, delegate
            {
                _eng.Log("INFO", "Watchdog exiting");
                _pollTimer.Stop();
                _edgeTimer.Stop();
                _tray.Visible = false;
                Close();
                Application.Exit();
            });
            _tray.ContextMenuStrip = menu;
            _tray.DoubleClick += delegate { _wantBar = true; ShowBar(); };

            _pollTimer = new System.Windows.Forms.Timer();
            _pollTimer.Interval = Math.Max(2000, eng.Cfg.PollSeconds * 1000);
            _pollTimer.Tick += delegate
            {
                Safe(delegate { _eng.Tick(); });
                RefreshUi();
                KeepTopMost();
            };

            _edgeTimer = new System.Windows.Forms.Timer();
            _edgeTimer.Interval = 200;
            _edgeTimer.Tick += delegate { HandleAutoHide(); };

            Shown += delegate
            {
                BootLog.Write("UI shown");
                _eng.Log("INFO", "Watchdog UI up. Player=" + _eng.Cfg.PlayerPath);
                if (_eng.Cfg.StartIfMissing)
                {
                    Process[] existing = new Process[0];
                    try { existing = Process.GetProcessesByName(_eng.Cfg.ProcessName); } catch { }
                    if (existing.Length == 0) _eng.StartPlayer();
                }
                Safe(delegate { _eng.Tick(); });
                RefreshUi();
                PlaceBar();
                if (_wantBar) ShowBar();
                else Hide();
                if (_autoHide && _wantBar) ArmHide();
            };
            FormClosing += delegate
            {
                _pollTimer.Stop();
                _edgeTimer.Stop();
                _tray.Visible = false;
            };
            MouseEnter += delegate { if (_autoHide) _hideAt = DateTime.MaxValue; };
            MouseLeave += delegate { if (_autoHide && _wantBar) ArmHide(); };

            _pollTimer.Start();
            _edgeTimer.Start();
        }

        protected override bool ShowWithoutActivation { get { return true; } }

        protected override CreateParams CreateParams
        {
            get
            {
                CreateParams cp = base.CreateParams;
                cp.ExStyle |= 0x00000008; // WS_EX_TOPMOST
                cp.ExStyle |= 0x08000000; // WS_EX_NOACTIVATE
                cp.ExStyle |= 0x00000080; // WS_EX_TOOLWINDOW
                return cp;
            }
        }

        private void PlaceBar()
        {
            Rectangle wa = Screen.PrimaryScreen.WorkingArea;
            Width = Math.Min(920, wa.Width);
            Left = wa.Left;
            if (string.Equals(_eng.Cfg.Dock, "top", StringComparison.OrdinalIgnoreCase))
                Top = wa.Top;
            else
                Top = wa.Bottom - Height;
        }

        private void ShowBar()
        {
            PlaceBar();
            if (!Visible) Show();
            KeepTopMost();
        }

        private void ArmHide()
        {
            _hideAt = DateTime.Now.AddSeconds(3);
        }

        private void HandleAutoHide()
        {
            if (!_wantBar) return;
            Point pt = Control.MousePosition;
            Rectangle wa = Screen.PrimaryScreen.WorkingArea;
            bool nearBottom = pt.Y >= (wa.Bottom - 10) && pt.X >= wa.Left && pt.X <= wa.Right;
            bool nearTop = pt.Y <= (wa.Top + 10) && pt.X >= wa.Left && pt.X <= wa.Right;
            bool overBar = Visible && Bounds.Contains(pt);
            bool hot = overBar ||
                       (string.Equals(_eng.Cfg.Dock, "top", StringComparison.OrdinalIgnoreCase) ? nearTop : nearBottom);

            if (_pinned)
            {
                if (!Visible) ShowBar();
                return;
            }

            if (!_autoHide) return;

            if (hot)
            {
                if (!Visible) ShowBar();
                _hideAt = DateTime.MaxValue;
            }
            else if (Visible && DateTime.Now >= _hideAt)
            {
                Hide();
            }
            else if (Visible && _hideAt == DateTime.MaxValue)
            {
                ArmHide();
            }
        }

        private void KeepTopMost()
        {
            try
            {
                Native.SetWindowPos(Handle, Native.HWND_TOPMOST, 0, 0, 0, 0,
                    Native.SWP_NOMOVE | Native.SWP_NOSIZE | Native.SWP_NOACTIVATE);
            }
            catch { }
        }

        private Button MakeButton(string text, int left, EventHandler click)
        {
            Button b = new Button();
            b.Text = text;
            b.FlatStyle = FlatStyle.Flat;
            b.FlatAppearance.BorderSize = 0;
            b.BackColor = Color.FromArgb(30, 41, 59);
            b.ForeColor = Color.White;
            b.Font = new Font("Segoe UI", 8);
            b.Width = 78;
            b.Height = 24;
            b.Left = left;
            b.Top = 6;
            b.Cursor = Cursors.Hand;
            b.Click += click;
            Controls.Add(b);
            return b;
        }

        private static Color StatusColor(string status)
        {
            switch (status)
            {
                case "RUNNING": return Color.FromArgb(16, 185, 129);
                case "STARTING": return Color.FromArgb(245, 158, 11);
                case "HUNG":
                case "DOWN": return Color.FromArgb(239, 68, 68);
                case "PAUSED": return Color.FromArgb(148, 163, 184);
                default: return Color.FromArgb(59, 130, 246);
            }
        }

        private void RefreshUi()
        {
            _dot.ForeColor = StatusColor(_eng.LastStatus);
            string pidBit = _eng.LastPid.HasValue ? "PID " + _eng.LastPid.Value : "no PID";
            _lbl.Text = "Cloud+ Player  |  " + _eng.LastStatus + "  |  " + pidBit + "  |  " + _eng.LastAction;
            try { _tray.Text = "ImpactLED  " + _eng.LastStatus; } catch { }
            _btnPause.Text = _eng.Paused ? "Resume" : "Pause";
            _btnPin.Text = _pinned ? "Unpin" : "Pin";
        }

        private static void Safe(MethodInvoker fn)
        {
            try { fn(); }
            catch (Exception ex) { BootLog.Write("ERROR " + ex); }
        }
    }

    internal static class Program
    {
        [STAThread]
        private static void Main()
        {
            BootLog.Write("Process start " + Application.ExecutablePath);
            Application.SetUnhandledExceptionMode(UnhandledExceptionMode.CatchException);
            Application.ThreadException += delegate(object s, ThreadExceptionEventArgs e)
            {
                BootLog.Write("ThreadException " + e.Exception);
                try { MessageBox.Show(e.Exception.Message, "ImpactLED Watchdog"); } catch { }
            };
            AppDomain.CurrentDomain.UnhandledException += delegate(object s, UnhandledExceptionEventArgs e)
            {
                BootLog.Write("UnhandledException " + e.ExceptionObject);
            };

            bool created = false;
            Mutex mutex = null;
            try
            {
                mutex = new Mutex(true, @"Local\ImpactLED.PlayerWatchdog", out created);
            }
            catch (Exception ex)
            {
                BootLog.Write("Mutex error " + ex.Message);
                created = true;
            }

            if (!created)
            {
                BootLog.Write("Already running");
                MessageBox.Show(
                    "ImpactLED Player Watchdog is already running.\r\nLook for the tray icon near the clock.",
                    "ImpactLED Watchdog");
                return;
            }

            try
            {
                string exeDir = AppDomain.CurrentDomain.BaseDirectory;
                string cfgPath = Path.Combine(exeDir, "watchdog.ini");
                Config cfg = Config.Load(cfgPath);
                if (!File.Exists(cfgPath))
                {
                    try { cfg.Save(cfgPath); } catch { }
                }
                BootLog.Write("Config loaded Dock=" + cfg.Dock + " AutoHide=" + cfg.AutoHide + " Player=" + cfg.PlayerPath);

                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);
                Application.Run(new MainForm(new Engine(cfg)));
            }
            catch (Exception ex)
            {
                BootLog.Write("Fatal " + ex);
                try { MessageBox.Show(ex.ToString(), "ImpactLED Watchdog failed to start"); } catch { }
            }
            finally
            {
                if (mutex != null)
                {
                    try { if (created) mutex.ReleaseMutex(); } catch { }
                    mutex.Dispose();
                }
            }
        }
    }
}
