// RTX 2060 DLSS 5 Offline Test - lightweight per-user Windows installer.
// Built without a C runtime; payload is embedded uncompressed for auditability.

typedef unsigned short wchar_t;
typedef unsigned char BYTE;
typedef unsigned long DWORD;
typedef long LONG;
typedef int BOOL;
typedef unsigned int UINT;
typedef unsigned long long ULONG_PTR;
typedef unsigned long long WPARAM;
typedef long long LPARAM;
typedef long long LRESULT;
typedef void* HANDLE;
typedef void* HMODULE;
typedef void* HINSTANCE;
typedef void* HWND;
typedef void* HMENU;
typedef void* HKEY;
typedef const wchar_t* LPCWSTR;
typedef wchar_t* LPWSTR;
typedef const void* LPCVOID;
typedef void* LPVOID;
typedef BYTE* LPBYTE;

#define NULL ((void*)0)
#define TRUE 1
#define FALSE 0
#define MAX_PATHX 4096
#define INVALID_HANDLE_VALUE ((HANDLE)(long long)-1)
#define GENERIC_WRITE 0x40000000UL
#define FILE_SHARE_READ 0x00000001UL
#define CREATE_ALWAYS 2UL
#define FILE_ATTRIBUTE_NORMAL 0x00000080UL
#define INVALID_FILE_ATTRIBUTES 0xFFFFFFFFUL
#define MB_OK 0x00000000UL
#define MB_YESNO 0x00000004UL
#define MB_ICONQUESTION 0x00000020UL
#define MB_ICONINFORMATION 0x00000040UL
#define MB_ICONWARNING 0x00000030UL
#define IDYES 6
#define SW_HIDE 0
#define SW_SHOWNORMAL 1
#define WM_CREATE 0x0001
#define WM_DESTROY 0x0002
#define WM_CLOSE 0x0010
#define WM_COMMAND 0x0111
#define WM_SETFONT 0x0030
#define WS_CHILD 0x40000000UL
#define WS_VISIBLE 0x10000000UL
#define WS_CAPTION 0x00C00000UL
#define WS_SYSMENU 0x00080000UL
#define WS_MINIMIZEBOX 0x00020000UL
#define BS_PUSHBUTTON 0x00000000UL
#define COLOR_BTNFACE 15
#define IDC_ARROW 32512
#define DEFAULT_GUI_FONT 17
#define KEY_WRITE 0x00020006UL
#define REG_SZ 1UL
#define REG_DWORD 4UL
#define ERROR_SUCCESS 0L
#define HKEY_CURRENT_USER ((HKEY)(long long)(int)0x80000001u)

__declspec(dllimport) void __stdcall ExitProcess(UINT);
__declspec(dllimport) DWORD __stdcall GetEnvironmentVariableW(LPCWSTR, LPWSTR, DWORD);
__declspec(dllimport) HMODULE __stdcall GetModuleHandleW(LPCWSTR);
__declspec(dllimport) BOOL __stdcall CreateDirectoryW(LPCWSTR, LPVOID);
__declspec(dllimport) DWORD __stdcall GetFileAttributesW(LPCWSTR);
__declspec(dllimport) HANDLE __stdcall CreateFileW(LPCWSTR,DWORD,DWORD,LPVOID,DWORD,DWORD,HANDLE);
__declspec(dllimport) BOOL __stdcall WriteFile(HANDLE,LPCVOID,DWORD,DWORD*,LPVOID);
__declspec(dllimport) BOOL __stdcall CloseHandle(HANDLE);
__declspec(dllimport) BOOL __stdcall DeleteFileW(LPCWSTR);
__declspec(dllimport) BOOL __stdcall RemoveDirectoryW(LPCWSTR);
__declspec(dllimport) DWORD __stdcall GetModuleFileNameW(HMODULE,LPWSTR,DWORD);
__declspec(dllimport) BOOL __stdcall CopyFileW(LPCWSTR,LPCWSTR,BOOL);
__declspec(dllimport) LPWSTR __stdcall GetCommandLineW(void);
__declspec(dllimport) int __stdcall MessageBoxW(HWND,LPCWSTR,LPCWSTR,UINT);
__declspec(dllimport) unsigned short __stdcall RegisterClassW(const void*);
__declspec(dllimport) HWND __stdcall CreateWindowExW(DWORD,LPCWSTR,LPCWSTR,DWORD,int,int,int,int,HWND,HMENU,HINSTANCE,LPVOID);
__declspec(dllimport) LRESULT __stdcall DefWindowProcW(HWND,UINT,WPARAM,LPARAM);
__declspec(dllimport) BOOL __stdcall ShowWindow(HWND,int);
__declspec(dllimport) BOOL __stdcall UpdateWindow(HWND);
__declspec(dllimport) BOOL __stdcall GetMessageW(void*,HWND,UINT,UINT);
__declspec(dllimport) BOOL __stdcall TranslateMessage(const void*);
__declspec(dllimport) LRESULT __stdcall DispatchMessageW(const void*);
__declspec(dllimport) void __stdcall PostQuitMessage(int);
__declspec(dllimport) BOOL __stdcall DestroyWindow(HWND);
__declspec(dllimport) LRESULT __stdcall SendMessageW(HWND,UINT,WPARAM,LPARAM);
__declspec(dllimport) void* __stdcall LoadCursorW(HINSTANCE,LPCWSTR);
__declspec(dllimport) int __stdcall GetSystemMetrics(int);
__declspec(dllimport) void* __stdcall GetStockObject(int);
__declspec(dllimport) void* __stdcall CreateFontW(int,int,int,int,int,DWORD,DWORD,DWORD,DWORD,DWORD,DWORD,DWORD,DWORD,LPCWSTR);
__declspec(dllimport) BOOL __stdcall DeleteObject(void*);
__declspec(dllimport) HINSTANCE __stdcall ShellExecuteW(HWND,LPCWSTR,LPCWSTR,LPCWSTR,LPCWSTR,int);
__declspec(dllimport) LONG __stdcall RegCreateKeyExW(HKEY,LPCWSTR,DWORD,LPWSTR,DWORD,DWORD,LPVOID,HKEY*,DWORD*);
__declspec(dllimport) LONG __stdcall RegSetValueExW(HKEY,LPCWSTR,DWORD,DWORD,const BYTE*,DWORD);
__declspec(dllimport) LONG __stdcall RegCloseKey(HKEY);
__declspec(dllimport) LONG __stdcall RegDeleteTreeW(HKEY,LPCWSTR);

static DWORD wlen(const wchar_t* s){ DWORD n=0; if(!s)return 0; while(s[n])n++; return n; }
static void wcopy(wchar_t* d,const wchar_t* s){ while((*d++=*s++)){} }
static void wcat(wchar_t* d,const wchar_t* s){ while(*d)d++; while((*d++=*s++)){} }
static int weq_ci_char(wchar_t a,wchar_t b){ if(a>='A'&&a<='Z')a+=32; if(b>='A'&&b<='Z')b+=32; return a==b; }
static int wcontains_ci(const wchar_t* h,const wchar_t* n){
  DWORD nl=wlen(n); if(!nl)return 1; for(DWORD i=0;h[i];i++){ DWORD j=0; while(j<nl && h[i+j] && weq_ci_char(h[i+j],n[j]))j++; if(j==nl)return 1;} return 0;
}
static int exists(const wchar_t* p){ return GetFileAttributesW(p)!=INVALID_FILE_ATTRIBUTES; }
static void join(wchar_t* out,const wchar_t* a,const wchar_t* b){ wcopy(out,a); DWORD n=wlen(out); if(n && out[n-1]!='\\'){out[n]='\\';out[n+1]=0;} wcat(out,b); }
static void parent_of(wchar_t* out,const wchar_t* p){ wcopy(out,p); DWORD n=wlen(out); while(n>0){ if(out[n-1]=='\\'||out[n-1]=='/'){out[n-1]=0;return;} n--; } out[0]=0; }
static void mkdirs(const wchar_t* p){
  wchar_t t[MAX_PATHX]; wcopy(t,p); DWORD n=wlen(t);
  for(DWORD i=0;i<n;i++){ if((t[i]=='\\'||t[i]=='/') && i>2){ wchar_t c=t[i]; t[i]=0; CreateDirectoryW(t,NULL); t[i]=c; } }
  CreateDirectoryW(t,NULL);
}
static int write_bytes(const wchar_t* path,const unsigned char* data,DWORD size,int preserve){
  if(preserve && exists(path)) return 1;
  wchar_t par[MAX_PATHX]; parent_of(par,path); if(par[0])mkdirs(par);
  HANDLE h=CreateFileW(path,GENERIC_WRITE,FILE_SHARE_READ,NULL,CREATE_ALWAYS,FILE_ATTRIBUTE_NORMAL,NULL);
  if(h==INVALID_HANDLE_VALUE)return 0; DWORD wrote=0; BOOL ok=WriteFile(h,data,size,&wrote,NULL); CloseHandle(h); return ok && wrote==size;
}
static int write_ascii(const wchar_t* path,const char* s){ DWORD n=0; while(s[n])n++; return write_bytes(path,(const unsigned char*)s,n,0); }
static void reg_sz(HKEY k,const wchar_t* name,const wchar_t* value){ RegSetValueExW(k,name,0,REG_SZ,(const BYTE*)value,(wlen(value)+1)*2); }
static void reg_dw(HKEY k,const wchar_t* name,DWORD value){ RegSetValueExW(k,name,0,REG_DWORD,(const BYTE*)&value,4); }

/* Embedded payload bytes inserted by generate_installer.py. */
@@PAYLOAD@@
static const char sm_full[]="@echo off\r\ncall \"%LOCALAPPDATA%\\Programs\\RTX2060-DLSS5-Offline-Test\\RUN-DROP-VIDEO-HERE.bat\"\r\n";
static const char sm_probe[]="@echo off\r\ncall \"%LOCALAPPDATA%\\Programs\\RTX2060-DLSS5-Offline-Test\\RUN-PROBE-ONLY.bat\"\r\n";
static const char sm_download[]="@echo off\r\ncall \"%LOCALAPPDATA%\\Programs\\RTX2060-DLSS5-Offline-Test\\RUN-UPDATE-RENDERER.bat\"\r\n";
static const char sm_player[]="@echo off\r\ncall \"%LOCALAPPDATA%\\Programs\\RTX2060-DLSS5-Offline-Test\\RUN-DLSS-PLAYER.bat\"\r\n";
static const char sm_results[]="@echo off\r\nstart \"\" explorer.exe \"%LOCALAPPDATA%\\Programs\\RTX2060-DLSS5-Offline-Test\\results\"\r\n";
static const char sm_upstream[]="@echo off\r\nstart \"\" explorer.exe \"%LOCALAPPDATA%\\Programs\\RTX2060-DLSS5-Offline-Test\\upstream\"\r\n";
static const char sm_install[]="@echo off\r\nstart \"\" explorer.exe \"%LOCALAPPDATA%\\Programs\\RTX2060-DLSS5-Offline-Test\"\r\n";
static const char sm_readme[]="@echo off\r\nstart \"\" notepad.exe \"%LOCALAPPDATA%\\Programs\\RTX2060-DLSS5-Offline-Test\\README.md\"\r\n";
static const char sm_uninstall[]="@echo off\r\nstart \"\" \"%LOCALAPPDATA%\\Programs\\RTX2060-DLSS5-Offline-Test\\Uninstall.exe\" /uninstall\r\n";

static void startmenu_path(wchar_t* sm){
  wchar_t appdata[MAX_PATHX]; appdata[0]=0; GetEnvironmentVariableW(L"APPDATA",appdata,MAX_PATHX);
  wcopy(sm,appdata); wcat(sm,L"\\Microsoft\\Windows\\Start Menu\\Programs\\RTX 2060 DLSS 5 Offline Test");
}
static void install_path(wchar_t* install){
  wchar_t local[MAX_PATHX]; local[0]=0; GetEnvironmentVariableW(L"LOCALAPPDATA",local,MAX_PATHX);
  if(!local[0]){ GetEnvironmentVariableW(L"USERPROFILE",local,MAX_PATHX); wcat(local,L"\\AppData\\Local"); }
  wcopy(install,local); wcat(install,L"\\Programs\\RTX2060-DLSS5-Offline-Test");
}
static void write_start_menu(void){
  wchar_t sm[MAX_PATHX],p[MAX_PATHX]; startmenu_path(sm); mkdirs(sm);
  join(p,sm,L"Full Offline Test.cmd"); write_ascii(p,sm_full);
  join(p,sm,L"Probe Only.cmd"); write_ascii(p,sm_probe);
  join(p,sm,L"Download or Update Renderer.cmd"); write_ascii(p,sm_download);
  join(p,sm,L"Open DLSS Video Player.cmd"); write_ascii(p,sm_player);
  join(p,sm,L"Open Results Folder.cmd"); write_ascii(p,sm_results);
  join(p,sm,L"Open Upstream Runtime Folder.cmd"); write_ascii(p,sm_upstream);
  join(p,sm,L"Open Install Folder.cmd"); write_ascii(p,sm_install);
  join(p,sm,L"Read README.cmd"); write_ascii(p,sm_readme);
  join(p,sm,L"Uninstall.cmd"); write_ascii(p,sm_uninstall);
}
static void delete_start_menu(void){
  wchar_t sm[MAX_PATHX],p[MAX_PATHX]; startmenu_path(sm);
  const wchar_t* names[]={L"Full Offline Test.cmd",L"Probe Only.cmd",
    L"Download or Update Renderer.cmd",L"Open DLSS Video Player.cmd",
    L"Open Results Folder.cmd",L"Open Upstream Runtime Folder.cmd",
    L"Open Install Folder.cmd",L"Read README.cmd",L"Uninstall.cmd"};
  for(DWORD i=0;i<9;i++){ join(p,sm,names[i]); DeleteFileW(p); } RemoveDirectoryW(sm);
}
static void register_uninstall(const wchar_t* install){
  HKEY k=NULL; DWORD disp=0; const wchar_t* sub=L"Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\RTX2060-DLSS5-Offline-Test";
  if(RegCreateKeyExW(HKEY_CURRENT_USER,sub,0,NULL,0,KEY_WRITE,NULL,&k,&disp)!=ERROR_SUCCESS)return;
  wchar_t u[MAX_PATHX],q[MAX_PATHX],icon[MAX_PATHX]; join(u,install,L"Uninstall.exe");
  wcopy(q,L"\""); wcat(q,u); wcat(q,L"\" /uninstall"); wcopy(icon,u);
  reg_sz(k,L"DisplayName",L"RTX 2060 DLSS 5 Offline Video Test");
  reg_sz(k,L"DisplayVersion",L"0.2.0");
  reg_sz(k,L"Publisher",L"Local R&D Tool");
  reg_sz(k,L"InstallLocation",install);
  reg_sz(k,L"UninstallString",q);
  reg_sz(k,L"DisplayIcon",icon);
  reg_dw(k,L"NoModify",1); reg_dw(k,L"NoRepair",1); RegCloseKey(k);
}
static void unregister_uninstall(void){
  RegDeleteTreeW(HKEY_CURRENT_USER,L"Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\RTX2060-DLSS5-Offline-Test");
}
// Windows x64 completion window. The renderer downloader is opt-in and
// runs in a separate, visible console window; do not execute downloads silently.
typedef LRESULT (__stdcall *WNDPROC)(HWND,UINT,WPARAM,LPARAM);
typedef struct {
  UINT style; WNDPROC lpfnWndProc; int cbClsExtra; int cbWndExtra;
  HINSTANCE hInstance; void* hIcon; void* hCursor; void* hbrBackground;
  LPCWSTR lpszMenuName; LPCWSTR lpszClassName;
} WNDCLASSW_LOCAL;
typedef struct { LONG x; LONG y; } POINT_LOCAL;
typedef struct {
  HWND hwnd; UINT message; WPARAM wParam; LPARAM lParam;
  DWORD time; POINT_LOCAL pt; DWORD lPrivate;
} MSG_LOCAL;
static wchar_t finished_install_dir[MAX_PATHX];
static int finished_runtime_found=0;
static int finished_download_started=0;
static void* finished_heading_font=NULL;
static HWND finish_add(HWND parent,const wchar_t* kind,const wchar_t* caption,int x,int y,int w,int h,int id){
  HWND child=CreateWindowExW(0,kind,caption,WS_CHILD|WS_VISIBLE,x,y,w,h,parent,(HMENU)(ULONG_PTR)id,GetModuleHandleW(NULL),NULL);
  if(child)SendMessageW(child,WM_SETFONT,(WPARAM)GetStockObject(DEFAULT_GUI_FONT),1);
  return child;
}
static void finish_launch(HWND wnd,const wchar_t* rel){
  wchar_t target[MAX_PATHX]; join(target,finished_install_dir,rel);
  ShellExecuteW(wnd,L"open",target,NULL,finished_install_dir,SW_SHOWNORMAL);
}
static LRESULT __stdcall finish_window_proc(HWND wnd,UINT msg,WPARAM w,LPARAM l){
  if(msg==WM_CREATE){
    HWND header=finish_add(wnd,L"STATIC",L"Offline Test installed successfully",30,26,735,45,0);
    if(header && finished_heading_font)SendMessageW(header,WM_SETFONT,(WPARAM)finished_heading_font,1);
    if(finished_download_started){
      finish_add(wnd,L"STATIC",
        L"The latest DLSS Video Player download has started in a separate console window.\r\n"
        L"Keep that window open until it says SUCCESS. The installer can now be closed.\r\n"
        L"The download is verified before activation and existing runtime files are backed up.",
        30,91,735,110,0);
    }else if(finished_runtime_found){
      finish_add(wnd,L"STATIC",
        L"Your existing DLSS Video Player runtime was preserved.\r\n"
        L"Choose Download / Update Renderer to fetch the newest complete release.\r\n"
        L"Or open your current player / run a quick compatibility probe.",
        30,91,735,110,0);
    }else{
      finish_add(wnd,L"STATIC",
        L"The offline-test harness is installed. The third-party neural runtime is not bundled.\r\n"
        L"Choose Download / Update Renderer for the newest complete release from GitHub.\r\n"
        L"This is a modified, unsigned community runtime, not official NVIDIA software.",
        30,91,735,110,0);
    }
    finish_add(wnd,L"STATIC",
      L"GitHub download ~377 MB at time of writing; download size may change with releases.\r\n"
      L"Results and previous versions are preserved. Update logs stay on your computer.",
      30,224,735,60,0);
    finish_add(wnd,L"BUTTON",L"Download / Update Renderer",30,318,242,42,101);
    finish_add(wnd,L"BUTTON",L"Open DLSS Player",290,318,188,42,102);
    finish_add(wnd,L"BUTTON",L"Run Probe Only",497,318,180,42,103);
    finish_add(wnd,L"BUTTON",L"Open Runtime Folder",30,385,185,38,104);
    finish_add(wnd,L"BUTTON",L"Read README",232,385,151,38,105);
    finish_add(wnd,L"BUTTON",L"Finish",605,385,130,38,106);
    return 0;
  }
  if(msg==WM_COMMAND){
    UINT id=(UINT)(w & 0xffff);
    if(id==101){finish_launch(wnd,L"RUN-UPDATE-RENDERER.bat"); return 0;}
    if(id==102){finish_launch(wnd,L"RUN-DLSS-PLAYER.bat"); return 0;}
    if(id==103){finish_launch(wnd,L"RUN-PROBE-ONLY.bat"); return 0;}
    if(id==104){ wchar_t t[MAX_PATHX]; join(t,finished_install_dir,L"upstream"); ShellExecuteW(wnd,L"open",t,NULL,NULL,SW_SHOWNORMAL); return 0; }
    if(id==105){ wchar_t t[MAX_PATHX]; join(t,finished_install_dir,L"README.md"); ShellExecuteW(wnd,L"open",L"notepad.exe",t,finished_install_dir,SW_SHOWNORMAL); return 0; }
    if(id==106){ DestroyWindow(wnd); return 0; }
  }
  if(msg==WM_CLOSE){ DestroyWindow(wnd); return 0; }
  if(msg==WM_DESTROY){ PostQuitMessage(0); return 0; }
  return DefWindowProcW(wnd,msg,w,l);
}
static void show_finished_window(const wchar_t* install,int runtime_found,int download_started){
  wcopy(finished_install_dir,install); finished_runtime_found=runtime_found; finished_download_started=download_started;
  HINSTANCE inst=GetModuleHandleW(NULL);
  WNDCLASSW_LOCAL wc={0}; wc.lpfnWndProc=finish_window_proc; wc.hInstance=inst;
  wc.hCursor=LoadCursorW(NULL,(LPCWSTR)(ULONG_PTR)IDC_ARROW);
  wc.hbrBackground=(void*)(ULONG_PTR)(COLOR_BTNFACE+1);
  wc.lpszClassName=L"RTX2060OfflineTestFinishPageV2";
  if(!RegisterClassW(&wc)){
    MessageBoxW(NULL,L"Installed. Use the Start Menu > Download or Update Renderer shortcut to get the complete DLSS player.",L"RTX 2060 DLSS 5 Offline Test",MB_OK|MB_ICONINFORMATION);
    return;
  }
  finished_heading_font=CreateFontW(-25,0,0,0,600,0,0,0,1,0,0,0,0,L"Segoe UI");
  int ww=808,wh=505;
  int px=(GetSystemMetrics(0)-ww)/2; int py=(GetSystemMetrics(1)-wh)/2;
  if(px<0)px=0; if(py<0)py=0;
  HWND wnd=CreateWindowExW(0,wc.lpszClassName,L"RTX 2060 DLSS 5 Offline Test Setup",
    WS_CAPTION|WS_SYSMENU|WS_MINIMIZEBOX,px,py,ww,wh,NULL,NULL,inst,NULL);
  if(!wnd){ MessageBoxW(NULL,L"Installed successfully. Use the Start Menu shortcuts to download or open the upstream player.",L"RTX 2060 DLSS 5 Offline Test",MB_OK|MB_ICONINFORMATION); }
  else{
    ShowWindow(wnd,SW_SHOWNORMAL); UpdateWindow(wnd);
    MSG_LOCAL m;
    while(GetMessageW(&m,NULL,0,0)>0){ TranslateMessage(&m); DispatchMessageW(&m); }
  }
  if(finished_heading_font){DeleteObject(finished_heading_font); finished_heading_font=NULL;}
}
static int do_install(void){
  int ans=MessageBoxW(NULL,
    L"Install the RTX 2060 DLSS 5 Offline Test for this Windows user?\n\n"
    L"After installation you may download the newest complete DLSS Video Player \n"
    L"from the upstream GitHub releases, including its modified, unsigned runtime.\n"
    L"Existing results and upstream files will be preserved.",
    L"RTX 2060 DLSS 5 Offline Test Setup",MB_YESNO|MB_ICONQUESTION);
  if(ans!=IDYES)return 0;
  wchar_t install[MAX_PATHX],dst[MAX_PATHX],self[MAX_PATHX]; install_path(install); mkdirs(install);
  DWORD failures=0;
  for(DWORD i=0;i<payload_count;i++){
    join(dst,install,payload[i].rel);
    if(!write_bytes(dst,payload[i].data,payload[i].size,payload[i].preserve))failures++;
  }
  GetModuleFileNameW(NULL,self,MAX_PATHX); join(dst,install,L"Uninstall.exe");
  if(!CopyFileW(self,dst,FALSE))failures++;
  if(failures){
    MessageBoxW(NULL,L"Some installation files could not be written. Check file permissions or antivirus and reinstall.",L"RTX 2060 DLSS 5 Offline Test",MB_OK|MB_ICONWARNING);
    return 2;
  }
  write_start_menu(); register_uninstall(install);
  int launchDownload=0;
  int doDownload=MessageBoxW(NULL,
    L"Download the newest COMPLETE DLSS Video Player now?\n\n"
    L"Downloads the player and modified unsigned neural runtime from\n"
    L"2600th/dlss5-video-player GitHub Releases (about 377 MB currently).\n"
    L"Checks SHA-256 and the package manifest before installing.\n"
    L"Keeps your old runtime in upstream-backups if updating.\n\n"
    L"Yes = start download in a separate window. No = install harness only.",
    L"Download Latest Renderer?",MB_YESNO|MB_ICONQUESTION);
  if(doDownload==IDYES){
    wchar_t run[MAX_PATHX]; join(run,install,L"RUN-UPDATE-RENDERER.bat");
    HINSTANCE result=ShellExecuteW(NULL,L"open",run,NULL,install,SW_SHOWNORMAL);
    if((ULONG_PTR)result>32)launchDownload=1;
    else MessageBoxW(NULL,L"Could not start the downloader. Use the Start Menu > Download or Update Renderer shortcut instead.",L"Downloader did not start",MB_OK|MB_ICONWARNING);
  }
  wchar_t probe[MAX_PATHX]; join(probe,install,L"upstream\\DLSSVideoPlayer.exe");
  show_finished_window(install,exists(probe),launchDownload);
  return 0;
}
static int do_uninstall(void){
  int ans=MessageBoxW(NULL,
    L"Remove the RTX 2060 DLSS 5 Offline Test application files?\n\nGenerated results, update logs, version backups and the entire third-party upstream folder will be preserved.",
    L"Uninstall RTX 2060 DLSS 5 Offline Test",MB_YESNO|MB_ICONQUESTION);
  if(ans!=IDYES)return 0;
  wchar_t install[MAX_PATHX],p[MAX_PATHX]; install_path(install);
  for(DWORD i=0;i<payload_count;i++){ join(p,install,payload[i].rel); DeleteFileW(p); }
  delete_start_menu(); unregister_uninstall();
  join(p,install,L"patches"); RemoveDirectoryW(p);
  join(p,install,L"results"); RemoveDirectoryW(p);
  join(p,install,L"upstream"); RemoveDirectoryW(p);
  MessageBoxW(NULL,L"Application files were removed.\n\nIf the install folder remains, it contains preserved results, update logs, backups or third-party upstream runtime files.",L"RTX 2060 DLSS 5 Offline Test",MB_OK|MB_ICONINFORMATION);
  // Delete this running uninstaller after exit; remove install folder only if it becomes empty.
  ShellExecuteW(NULL,L"open",L"cmd.exe",
    L"/c ping 127.0.0.1 -n 2 >nul & del /f /q \"%LOCALAPPDATA%\\Programs\\RTX2060-DLSS5-Offline-Test\\Uninstall.exe\" & rmdir \"%LOCALAPPDATA%\\Programs\\RTX2060-DLSS5-Offline-Test\\patches\" 2>nul & rmdir \"%LOCALAPPDATA%\\Programs\\RTX2060-DLSS5-Offline-Test\\results\" 2>nul & rmdir \"%LOCALAPPDATA%\\Programs\\RTX2060-DLSS5-Offline-Test\\upstream\" 2>nul & rmdir \"%LOCALAPPDATA%\\Programs\\RTX2060-DLSS5-Offline-Test\" 2>nul",
    NULL,SW_HIDE);
  return 0;
}
void WinMainCRTStartup(void){
  wchar_t* cmd=GetCommandLineW();
  wchar_t self[MAX_PATHX]; self[0]=0; GetModuleFileNameW(NULL,self,MAX_PATHX);
  int uninstall_mode=wcontains_ci(cmd,L"/uninstall") || wcontains_ci(self,L"\\Uninstall.exe");
  int rc=uninstall_mode?do_uninstall():do_install(); ExitProcess((UINT)rc);
}
