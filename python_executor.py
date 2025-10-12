import subprocess
import tempfile
import os
import sys
import json
import base64
import platform
import glob
import traceback

class PythonExecutor:
    def __init__(self):
        print("[PythonExecutor] Initializing...")
        print(f"[PythonExecutor] sys.executable = {sys.executable}")
        print(f"[PythonExecutor] sys.frozen = {getattr(sys, 'frozen', False)}")
        print(f"[PythonExecutor] Platform = {platform.system()}")
        
        # Find system Python
        self.python_command = self._find_python()
        print(f"[PythonExecutor] Will use Python command: {self.python_command}")
    
    def _find_python(self):
        """Find system Python executable"""
        # If running as script (not frozen), use current Python
        if not getattr(sys, 'frozen', False):
            print(f"[PythonExecutor] Not frozen, using current Python: {sys.executable}")
            return sys.executable
        
        # Running as frozen exe - need to find system Python
        print("[PythonExecutor] Running as frozen exe, searching for system Python...")
        
        # Try simple commands first (fastest)
        simple_candidates = ['python3', 'python', 'py']
        
        for candidate in simple_candidates:
            print(f"[PythonExecutor] Testing candidate: {candidate}")
            if self._test_python(candidate):
                print(f"[PythonExecutor] SUCCESS! Using: {candidate}")
                return candidate
        
        # If on Windows, search common installation directories
        if platform.system() == "Windows":
            print("[PythonExecutor] Searching Windows directories...")
            search_paths = [
                r'C:\Python*\python.exe',
                r'C:\Program Files\Python*\python.exe',
                r'C:\Program Files (x86)\Python*\python.exe',
            ]
            
            # Add user directories if they exist
            if os.environ.get('LOCALAPPDATA'):
                search_paths.append(os.path.join(os.environ['LOCALAPPDATA'], 'Programs', 'Python', 'Python*', 'python.exe'))
            if os.environ.get('APPDATA'):
                search_paths.append(os.path.join(os.environ['APPDATA'], 'Python', 'Python*', 'python.exe'))
            
            for pattern in search_paths:
                print(f"[PythonExecutor] Searching pattern: {pattern}")
                try:
                    matches = glob.glob(pattern)
                    print(f"[PythonExecutor] Found {len(matches)} matches")
                    # Sort to get highest version first
                    for path in sorted(matches, reverse=True):
                        print(f"[PythonExecutor] Testing: {path}")
                        if self._test_python(path):
                            print(f"[PythonExecutor] SUCCESS! Using: {path}")
                            return path
                except Exception as e:
                    print(f"[PythonExecutor] Error searching {pattern}: {e}")
        
        # Last resort
        print("[PythonExecutor] WARNING: Could not find Python, defaulting to 'python'")
        return 'python'
    
    def _test_python(self, command):
        """Test if a Python executable works"""
        try:
            print(f"[PythonExecutor] Running '{command} --version'...")
            result = subprocess.run(
                [command, '--version'],
                capture_output=True,
                timeout=5,
                text=True
            )
            print(f"[PythonExecutor] Return code: {result.returncode}")
            if result.returncode == 0:
                version = result.stdout.strip() or result.stderr.strip()
                print(f"[PythonExecutor] Version output: {version}")
                return True
            else:
                print(f"[PythonExecutor] Failed with stdout={result.stdout}, stderr={result.stderr}")
        except FileNotFoundError as e:
            print(f"[PythonExecutor] FileNotFoundError: {e}")
        except subprocess.TimeoutExpired:
            print(f"[PythonExecutor] Timeout!")
        except PermissionError as e:
            print(f"[PythonExecutor] PermissionError: {e}")
        except Exception as e:
            print(f"[PythonExecutor] Unexpected error: {type(e).__name__}: {e}")
        return False
    
    def run_script(self, job_name, script_content, job_conf, input_path=None, job_digest=None):
        """
        Run the python script.
        """
        print(f"[PythonExecutor] run_script called for {job_name}")
        print(f"[PythonExecutor] Script length: {len(script_content)} chars")
        print(f"[PythonExecutor] Python command: {self.python_command}")
        
        # Write script to temp file
        try:
            with tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='.py') as f:
                f.write(script_content)
                f.flush()
                script_path = f.name
            print(f"[PythonExecutor] Script written to: {script_path}")
        except Exception as e:
            print(f"[PythonExecutor] ERROR writing script: {e}")
            return {
                "stdout": "",
                "stderr": f"Failed to write script: {e}",
                "retcode": -1
            }
        
        try:
            print(f"[PythonExecutor] Executing: {self.python_command} {script_path}")
            
            # Build command
            args = [self.python_command, script_path]
            if input_path:
                args.append(input_path)
                print(f"[PythonExecutor] Added input path: {input_path}")
            
            # Set up environment
            env = os.environ.copy()
            
            # Add job metadata to environment for script access
            if job_digest:
                env['JOB_DIGEST_ID'] = str(job_digest.get('id', ''))
                
                # Handle tags
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
            
            print(f"[PythonExecutor] Running subprocess...")
            result = subprocess.run(
                args, 
                capture_output=True, 
                text=True,
                timeout=job_conf.get('timeout', 300),
                env=env
            )
            
            print(f"[PythonExecutor:{job_name}] Exit={result.returncode}")
            if result.stdout:
                print(f"[PythonExecutor:{job_name}] STDOUT:\n{result.stdout}")
            if result.stderr:
                print(f"[PythonExecutor:{job_name}] STDERR:\n{result.stderr}")
            
            return {
                "stdout": result.stdout,
                "stderr": result.stderr,
                "retcode": result.returncode,
            }
            
        except subprocess.TimeoutExpired as e:
            print(f"[PythonExecutor:{job_name}] TIMEOUT after {job_conf.get('timeout', 300)}s")
            return {
                "stdout": "",
                "stderr": f"Script timed out after {job_conf.get('timeout', 300)} seconds",
                "retcode": -1
            }
        except FileNotFoundError as e:
            print(f"[PythonExecutor:{job_name}] FileNotFoundError: {e}")
            return {
                "stdout": "",
                "stderr": f"Python executable not found: {self.python_command}",
                "retcode": -1
            }
        except Exception as e:
            print(f"[PythonExecutor:{job_name}] EXCEPTION: {type(e).__name__}: {e}")
            print(f"[PythonExecutor:{job_name}] Traceback:\n{traceback.format_exc()}")
            return {
                "stdout": "",
                "stderr": str(e),
                "retcode": -1
            }
        finally:
            try:
                if 'script_path' in locals():
                    os.remove(script_path)
                    print(f"[PythonExecutor] Cleaned up {script_path}")
            except Exception as e:
                print(f"[PythonExecutor] Failed to cleanup: {e}")