import subprocess
import tempfile
import os

class BashExecutor:
    def run_script(self, job_name, script_content, job_conf, input_path=None, job_digest=None):
        """
        Run the bash script.
        If input_path is provided, script is called with input_path as first positional argument.
        Returns: dict of {"stdout": ..., "stderr": ..., "retcode": ...}
        """
        with tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='.sh') as f:
            f.write(script_content)
            f.flush()
            script_path = f.name
        try:
            print(f"[BashExecutor] Running {job_name} at {script_path}")
            args = ["bash", script_path]
            if input_path:
                args.append(input_path)
            result = subprocess.run(
                args, capture_output=True, text=True, 
                timeout=job_conf.get('timeout', 300)
            )
            print(f"[BashExecutor:{job_name}] Exit={result.returncode}")
            if result.stdout:
                print(f"[BashExecutor:{job_name}] STDOUT:\n{result.stdout}")
            if result.stderr:
                print(f"[BashExecutor:{job_name}] STDERR:\n{result.stderr}")
            return {
                "stdout": result.stdout,
                "stderr": result.stderr,
                "retcode": result.returncode,
            }
        except Exception as e:
            print(f"[BashExecutor:{job_name}] Failed: {e}")
            return {
                "stdout": "",
                "stderr": str(e),
                "retcode": -1
            }
        finally:
            os.remove(script_path)