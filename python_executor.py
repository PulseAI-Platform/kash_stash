import subprocess
import tempfile
import os
import sys
import json
import base64

class PythonExecutor:
    def run_script(self, job_name, script_content, job_conf, input_path=None, job_digest=None):
        """
        Run the python script.
        If input_path is provided, script is called with input_path as first positional argument.
        Returns: dict of {"stdout": ..., "stderr": ..., "retcode": ...}
        """
        # Write script to temp file
        with tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='.py') as f:
            f.write(script_content)
            f.flush()
            script_path = f.name
        
        try:
            print(f"[PythonExecutor] Running {job_name} at {script_path}")
            
            # Build command - use sys.executable to use same Python as agent
            args = [sys.executable, script_path]
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
            print(f"[PythonExecutor:{job_name}] Timeout after {job_conf.get('timeout', 300)}s")
            return {
                "stdout": "",
                "stderr": f"Script timed out after {job_conf.get('timeout', 300)} seconds",
                "retcode": -1
            }
        except Exception as e:
            print(f"[PythonExecutor:{job_name}] Failed: {e}")
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