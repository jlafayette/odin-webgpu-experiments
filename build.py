import subprocess
import shutil
import sys
import os
import stat
from pathlib import Path
from typing import NamedTuple


class Args(NamedTuple):
	project: str
	go: bool
	odin: bool
	optimized: bool
	run: bool


root_dir = Path(__file__).absolute().parent

INITIAL_MEMORY_PAGES = 2000
MAX_MEMORY_PAGES = 65536
PAGE_SIZE = 65536

INITIAL_MEMORY_BYTES = INITIAL_MEMORY_PAGES * PAGE_SIZE
MAX_MEMORY_BYTES = MAX_MEMORY_PAGES * PAGE_SIZE

def main(args: Args) -> Path:
	print(args)
	project_dst = Path(args.project)
	public_dst = project_dst / "public"
	if not public_dst.is_dir():
		print(f"No public folder found for project: {project_dst}")
		sys.exit(1)

	# check that memory settings match
	index_contents = (public_dst / "index.html").read_text()
	if not f'initial: {INITIAL_MEMORY_PAGES}' in index_contents:
		print("Initial memory does not match! Adjust either build.py or index.html")
		sys.exit(1)
	if not f'maximum: {MAX_MEMORY_PAGES}' in index_contents:
		print("Maximum memory does not match! Adjust either build.py or index.html")
		sys.exit(1)
	
	server_dst = public_dst / "main.exe"
	if args.go or not server_dst.exists():
		print("building server...")
		clean(server_dst)
		subprocess.run(["go", "build", "-o", server_dst, "main.go"], check=True)
	
	wasm_dst = public_dst / "_main.wasm"

	build_args = [
		"-target:js_wasm32",
	]
	if args.optimized:
		build_args.extend(["-o:speed"])
		# -disable-assert and -no-bounds-check are causing some issues
		# needs more investigcation
		# build_args.extend(["-o:speed", "-disable-assert", "-no-bounds-check"])
	else:
		build_args.extend(["-o:minimal"])
	build_args.append(
		f'-extra-linker-flags:"--export-table --import-memory --initial-memory={INITIAL_MEMORY_BYTES} --max-memory={MAX_MEMORY_BYTES}"'
	)

	if args.odin or not wasm_dst.exists():
		print("building wasm...")
		clean(wasm_dst)
		print(build_args)
		# print("---")
		# subprocess.run(
	 #        [
		# 		"python", "t.py", "build", project_dst, f"-out:{wasm_dst.as_posix()}",
	 #        ] + build_args, check=True)
		# print("---")
		bat = Path("tmp.bat")
		generate_bat_file(bat, ["build", str(project_dst), f"-out:{wasm_dst.as_posix()}"] + build_args)
		subprocess.run(bat)
		# print("---")
		# subprocess.run(
	 #        [
	 #        	"cmd.exe", "/c",
		# 		"odin", "build", project_dst, f"-out:{wasm_dst}",
	 #        ] + build_args, check=True)
		# print("---")

	for odin_src_subpath, filename in [
		("core/sys/wasm/js", "odin.js"),
		("vendor/wgpu", "wgpu.js"),
	]:
		js_dst = public_dst / filename
		clean(js_dst)
		r = subprocess.check_output(["odin", "root"])
		src = Path(r.decode()) / odin_src_subpath / filename
		shutil.copy(src, js_dst)

	for src_folder, filename in [
		("resize", "odin-resize.js"),
		# ("gamepad", "odin-gamepad.js"),
		# ("cursor", "odin-cursor.js"),
	]:
		js_dst = public_dst / filename
		clean(js_dst)
		shutil.copy(root_dir / "shared" / src_folder / filename, js_dst)

	if args.run:
		bat = public_dst / "tmp.bat"
		generate_bat_file(bat, ["build", "../", "-out:_main.wasm"] + build_args)

		os.chdir(public_dst)
		# r = subprocess.check_output(["odin", "root"])
		# odin_exe = Path(r.decode()) / "odin"
		cmd = [server_dst.name, bat.name]
		try:
			print("cmd:", cmd)
			subprocess.run(cmd, shell=True, check=True)
		except KeyboardInterrupt:
			print("Shutting down server")
			sys.exit(0)

	return public_dst


def generate_bat_file(out: Path, args: list[str]):
	"""This works around a problem where odin isn't reading the extra-linker args right.

	This happens when calling from subprocess.run or from go dev server.
	For whatever reason, calling it from .bat script works.

	"""
	contents = f"""
call odin.exe {' '.join(args)}
"""
	out.write_text(contents)
	st = out.stat()
	current_permissions = st.st_mode
	new_permissions = current_permissions | stat.S_IEXEC | stat.S_IXGRP | stat.S_IXOTH
	out.chmod(new_permissions)


def clean(p: Path):
	if p.is_file():
		p.unlink()
	elif p.is_dir():
		shutil.rmtree(p)


def copy_odin_js(dst: Path):
	# <!-- Copy `vendor:wasm/js/runtime.js` into your web server -->
	r = subprocess.check_output(["odin", "root"])
	src = Path(r.decode()) / "core/sys/wasm/js/odin.js"
	shutil.copy(src, dst)


def args():
	args = sys.argv[1:]
	if len(args) == 0:
		print("select project to run")
		sys.exit(1)
	build_go = "-g" in args
	build_odin = "--odin" in args
	optimize = "-o" in args or "--optimize" in args
	run = "--no-run" not in args
	return Args(args[0], build_go, build_odin, optimize, run)


if __name__ == "__main__":
	main(args())
