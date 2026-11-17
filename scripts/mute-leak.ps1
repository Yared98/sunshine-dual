<#
    mute-leak.ps1 -- mute the RDP-redirected audio leak on the console.

    The SwitchGamer session streams via Apollo capturing its "Remote Audio"
    endpoint. With RDP audio redirection on (audiomode:i:0, needed so the
    session HAS an audio device to capture), that audio is also sent to the
    mstsc client on the console and plays on the host user's speakers. This
    mutes mstsc per-app (per-user, no admin) so the host user does not hear the
    streaming user's game. The capture inside the SwitchGamer session is unaffected.

    The mstsc audio session only exists while audio is actually playing, so a
    one-shot mute right after connect may find nothing. Run with -Loop to poll
    and mute mstsc as soon as it appears, exiting when no SwitchGamer session
    remains (or after -TimeoutMin minutes).

      .\mute-leak.ps1              # one-shot
      .\mute-leak.ps1 -Loop        # poll + mute until the session ends
#>
param(
    [string]$ProcName   = 'mstsc',
    [switch]$Loop,
    [int]   $IntervalSec= 3,
    [int]   $TimeoutMin = 600,
    [switch]$Unmute
)

$code = @'
using System;
using System.Runtime.InteropServices;
namespace LeakMute {
  [Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IMMDeviceEnumerator { int EnumAudioEndpoints(int dataFlow,int mask,out IMMDeviceCollection col); int GetDefaultAudioEndpoint(int d,int r,out IMMDevice ep); }
  [Guid("0BD7A1BE-7A1A-44DB-8397-CC5392387B5E"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IMMDeviceCollection { int GetCount(out int c); int Item(int i,out IMMDevice d); }
  [Guid("D666063F-1587-4E43-81F1-B948E807363F"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IMMDevice { int Activate(ref Guid iid,int ctx,IntPtr p,[MarshalAs(UnmanagedType.IUnknown)]out object o); int OpenPropertyStore(int a,out IntPtr ps); int GetId(out IntPtr id); int GetState(out int s); }
  [Guid("77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IAudioSessionManager2 { int d1();int d2(); int GetSessionEnumerator(out IAudioSessionEnumerator e); }
  [Guid("E2F5BB11-0570-40CA-ACDD-3AA01277DEE8"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IAudioSessionEnumerator { int GetCount(out int c); int GetSession(int i,out IAudioSessionControl s); }
  [Guid("F4B1A599-7266-4319-A8CA-E70ACB11E8CD"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IAudioSessionControl { int GetState(out int s); int m2();int m3();int m4();int m5();int m6();int m7();int m8();int m9(); }
  [Guid("BFB7FF88-7239-4FC9-8FA2-07C950BE9C6D"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IAudioSessionControl2 { int GetState(out int s); int m2();int m3();int m4();int m5();int m6();int m7();int m8();int m9(); int GetSessionIdentifier(out IntPtr id); int GetSessionInstanceIdentifier(out IntPtr id); int GetProcessId(out uint pid); int IsSystemSoundsSession(); int SetDuckingPreference(bool b); }
  [Guid("87CE5498-68D6-44E5-9215-6DA47EF883D8"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface ISimpleAudioVolume { int SetMasterVolume(float l,ref Guid ev); int GetMasterVolume(out float l); int SetMute(bool m,ref Guid ev); int GetMute(out bool m); }
  public static class M {
    public static int Do(string proc,bool mute){
      int done=0;
      Type t=Type.GetTypeFromCLSID(new Guid("BCDE0395-E52F-467C-8E3D-C4579291692E"));
      var en=(IMMDeviceEnumerator)Activator.CreateInstance(t);
      IMMDeviceCollection col; en.EnumAudioEndpoints(0,1,out col); int n; col.GetCount(out n);
      Guid IID=new Guid("77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F"); Guid empty=Guid.Empty;
      for(int i=0;i<n;i++){ IMMDevice dev; col.Item(i,out dev);
        object o; try{ dev.Activate(ref IID,1,IntPtr.Zero,out o);}catch{continue;}
        var mgr=(IAudioSessionManager2)o; IAudioSessionEnumerator se; if(mgr.GetSessionEnumerator(out se)!=0) continue;
        int cnt; se.GetCount(out cnt);
        for(int j=0;j<cnt;j++){ IAudioSessionControl c; if(se.GetSession(j,out c)!=0||c==null) continue;
          var c2=(IAudioSessionControl2)c; uint pid; if(c2.GetProcessId(out pid)!=0) continue;
          string pn=null; try{ pn=System.Diagnostics.Process.GetProcessById((int)pid).ProcessName;}catch{continue;}
          if(pn!=null && pn.Equals(proc,StringComparison.OrdinalIgnoreCase)){
            var sv=(ISimpleAudioVolume)c; bool cur; sv.GetMute(out cur);
            if(cur!=mute){ sv.SetMute(mute,ref empty); done++; }
          }
        }
      }
      return done;
    }
  }
}
'@
Add-Type -TypeDefinition $code -Language CSharp -ErrorAction SilentlyContinue
$target = -not $Unmute

. (Join-Path $PSScriptRoot 'config.ps1')
function Test-SwitchSession {
    $out = qwinsta 2>$null | Select-String $SD_User
    return [bool]($out -and ($out.ToString() -match '\s\d+\s+(Active|Disc|Disconnected)'))
}

if (-not $Loop) {
    $n = [LeakMute.M]::Do($ProcName, $target)
    Write-Host "[mute-leak] mstsc alterado: $n"
    return
}

Write-Host "[mute-leak] loop: silenciando $ProcName enquanto a sessao SwitchGamer existir."
$deadline = (Get-Date).AddMinutes($TimeoutMin)
while ((Get-Date) -lt $deadline) {
    if (-not (Test-SwitchSession)) { Write-Host "[mute-leak] sessao SwitchGamer encerrada; saindo."; break }
    try { [void][LeakMute.M]::Do($ProcName, $true) } catch {}
    Start-Sleep -Seconds $IntervalSec
}
