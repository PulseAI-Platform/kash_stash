import subprocess
import tempfile
import os
import sys
import platform

class PowerShellExecutor:
    def __init__(self):
        # Detect the right PowerShell command based on platform
        if platform.system() == "Windows":
            # On Windows, prefer pwsh (PowerShell Core) if available, else fallback to powershell
            self.ps_command = self._find_powershell_windows()
        else:
            # On Linux/Mac, use pwsh (PowerShell Core)
            self.ps_command = "pwsh"
    
    def _find_powershell_windows(self):
        """Find the best PowerShell executable on Windows"""
        # Try PowerShell Core first
        try:
            result = subprocess.run(["pwsh", "-Version"], capture_output=True, timeout=5)
            if result.returncode == 0:
                return "pwsh"
        except:
            pass
        
        # Fallback to Windows PowerShell
        try:
            result = subprocess.run(["powershell", "-Version"], capture_output=True, timeout=5)
            if result.returncode == 0:
                return "powershell"
        except:
            pass
        
        # Last resort - full path to Windows PowerShell
        return r"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"
    
    def run_script(self, job_name, script_content, job_conf, input_path=None, job_digest=None):
        """
        Run the PowerShell script.
        If input_path is provided, script is called with input_path as first positional argument.
        Returns: dict of {"stdout": ..., "stderr": ..., "retcode": ...}
        """
        # Write script to temp file with .ps1 extension
        with tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='.ps1', encoding='utf-8') as f:
            # Add UTF-8 BOM for Windows PowerShell compatibility
            if platform.system() == "Windows" and self.ps_command == "powershell":
                f.write('\ufeff')  # UTF-8 BOM
            f.write(script_content)
            f.flush()
            script_path = f.name
        
        try:
            print(f"[PowerShellExecutor] Running {job_name} at {script_path}")
            
            # Build command
            # -NoProfile: Don't load profile (faster)
            # -NonInteractive: Don't prompt
            # -ExecutionPolicy Bypass: Allow script execution
            # -File: Run script file
            args = [
                self.ps_command,
                "-NoProfile",
                "-NonInteractive", 
                "-ExecutionPolicy", "Bypass",
                "-File", script_path
            ]
            
            if input_path:
                args.append(input_path)
            
            # Set up environment
            env = os.environ.copy()
            
            # Add job metadata to environment for script access
            if job_digest:
                env['JOB_DIGEST_ID'] = str(job_digest.get('id', ''))
                
                # Fix: Handle tags whether they're dicts or strings
                tags = job_digest.get('tags', [])
                if isinstance(tags, list):
                    tag_names = []
                    for tag in tags:
                        if isinstance(tag, dict):
                            tag_names.append(tag.get('name', ''))
                        else:
                            tag_names.append(str(tag))
                    env['JOB_DIGEST_TAGS'] = ','.join(tag_names)
                else:
                    env['JOB_DIGEST_TAGS'] = str(tags)
                    
            env['JOB_NAME'] = job_name
            env['JOB_TYPE'] = job_conf.get('type', '')
            
            result = subprocess.run(
                args,
                capture_output=True,
                text=True,
                timeout=job_conf.get('timeout', 300),
                env=env,
                encoding='utf-8',
                errors='replace'  # Handle any encoding issues gracefully
            )
            
            print(f"[PowerShellExecutor:{job_name}] Exit={result.returncode}")
            if result.stdout:
                print(f"[PowerShellExecutor:{job_name}] STDOUT:\n{result.stdout}")
            if result.stderr:
                print(f"[PowerShellExecutor:{job_name}] STDERR:\n{result.stderr}")
            
            return {
                "stdout": result.stdout,
                "stderr": result.stderr,
                "retcode": result.returncode,
            }
        except subprocess.TimeoutExpired as e:
            print(f"[PowerShellExecutor:{job_name}] Timeout after {job_conf.get('timeout', 300)}s")
            return {
                "stdout": "",
                "stderr": f"Script timed out after {job_conf.get('timeout', 300)} seconds",
                "retcode": -1
            }
        except FileNotFoundError:
            error_msg = f"PowerShell not found. Please install PowerShell Core (pwsh) from https://github.com/PowerShell/PowerShell"
            print(f"[PowerShellExecutor:{job_name}] {error_msg}")
            return {
                "stdout": "",
                "stderr": error_msg,
                "retcode": -1
            }
        except Exception as e:
            print(f"[PowerShellExecutor:{job_name}] Failed: {e}")
            return {
                "stdout": "",
                "stderr": str(e),
                "retcode": -1
            }
        finally:
            try:
                os.remove(script_path)
            except:
                pass