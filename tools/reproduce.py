"""Offline reproduction entry. Default is a checked plan; --execute is explicit.
No hardware, media formatting, Flash or JTAG actions are implemented.
"""
from pathlib import Path
import argparse,subprocess,datetime,shutil,json,os,hashlib
P=Path(__file__).resolve().parents[1]
a=argparse.ArgumentParser();a.add_argument('stage',choices=['implement','export','app','fsbl','boot','sim'])
a.add_argument('--local-inputs', type=Path, default=P/'local_inputs')
a.add_argument('--vectors', type=Path, default=P/'reproduced/vectors')
a.add_argument('--checkpoint');a.add_argument('--xsa');a.add_argument('--fsbl');a.add_argument('--bit');a.add_argument('--app-elf');
a.add_argument('--execute',action='store_true');a.add_argument('--vivado',default=os.environ.get('VIVADO_2020_2','vivado_2020_2_not_configured'))
a.add_argument('--vitis',default=os.environ.get('VITIS_2020_2','vitis_2020_2_not_configured'));v=a.parse_args()
H=P/'src/hardware';APP=P/'src/software/app';VB=Path(v.vivado)/'bin';VT=Path(v.vitis)/'bin'
OUT=P/'reproduced'/datetime.datetime.now().strftime('%Y%m%d_%H%M%S')/v.stage
files=[];cmds=[];copies=[]
def verified_files(root, expected, instruction):
    files = []
    errors = []
    for name, digest in expected.items():
        path = root / name
        if not path.is_file():
            errors.append(f'{name}: missing')
        elif hashlib.sha256(path.read_bytes()).hexdigest() != digest:
            errors.append(f'{name}: SHA-256 mismatch')
        else:
            files.append(path)
    if errors:
        raise SystemExit(instruction + '\n' + '\n'.join(errors))
    return files

if v.stage=='implement':
    board = v.local_inputs.resolve()
    local = json.loads((P/'docs/local_inputs.json').read_text(encoding='utf8'))
    board_files = verified_files(board, {n: i['sha256'] for n, i in local.items()},
                                 'Supply the authorized board inputs listed in docs/local_inputs.json.')
    files = [H/'scripts'/n for n in ['implement.tcl','prepare.tcl','review_fifo_cdc.tcl']]
    files += [H/'constraints'/n for n in ['pins.xdc','timing.xdc']]
    files += sorted((H/'rtl').glob('*.v')) + sorted((H/'rtl').glob('*.sv')) + board_files
    cmds = [[VB/'vivado.bat','-mode','batch','-nojournal','-log','vivado.log',
             '-source',H/'scripts/implement.tcl','-tclargs',H,board]]
elif v.stage=='export':
 if not v.checkpoint:raise SystemExit('Source-only candidate: export requires --checkpoint <new routed.dcp>')
 d=Path(v.checkpoint).resolve();files=[d,H/'scripts/export.tcl',H/'scripts/review_fifo_cdc.tcl']
 expected_dcp=hashlib.sha256(d.read_bytes()).hexdigest()
 cmds=[[VB/'vivado.bat','-mode','batch','-nojournal','-log','vivado.log','-source',H/'scripts/export.tcl','-tclargs',H,d,expected_dcp]]
elif v.stage=='app':
 cc=Path(v.vitis)/'gnu/aarch32/nt/gcc-arm-none-eabi/bin/arm-none-eabi-gcc.exe'
 files=[APP/x for x in ['start.s','link.ld','standalone_main.c','demo_fsm.c','demo_fsm.h']]
 cmds=[[cc,'-mcpu=cortex-a9','-marm','-O2','-ffreestanding','-fno-builtin','-nostdlib','-fno-stack-protector','-Wall','-Wextra','-Werror','-T',APP/'link.ld','-Wl,-Map=standalone.map','-x','assembler-with-cpp',APP/'start.s','-x','c',APP/'standalone_main.c',APP/'demo_fsm.c','-x','none','-lgcc','-o','standalone.elf']]
elif v.stage=='fsbl':
 if not v.xsa:raise SystemExit('Source-only candidate: fsbl requires --xsa <fresh exported .xsa>')
 x=Path(v.xsa).resolve();t=P/'tools/hsi_fsbl.tcl';files=[x,t]
 cmds=[[VT/'xsct.bat',t,x,OUT/'fsbl_generated']]
elif v.stage=='boot':
 if not all([v.fsbl,v.bit,v.app_elf]):raise SystemExit('Source-only candidate: boot requires --fsbl --bit --app-elf <fresh build files>')
 files=[Path(v.fsbl).resolve(),Path(v.bit).resolve(),Path(v.app_elf).resolve(),P/'tools/boot.bif']
 copies=list(zip(files,['fsbl.elf','system.bit','standalone.elf','boot.bif']))
 cmds=[[VT/'bootgen.bat','-arch','zynq','-image','boot.bif','-o','BOOT.BIN','-log','info'],[VT/'bootgen.bat','-arch','zynq','-read','BOOT.BIN']]
elif v.stage=='sim':
    rtl = [H/'rtl'/n for n in ['win3x3.v','comic_core.v','comic_axis.sv']]
    testbench = P/'sim/tb_quality.sv'
    manifest = json.loads((P/'data/quality_vectors/manifest.json').read_text(encoding='utf8'))
    vectors = verified_files(v.vectors.resolve(), {x['name']: x['sha256'] for x in manifest['files']},
                             'Generate the vectors as described in readme.md before running sim.')
    files = rtl + [testbench] + vectors
    copies = [(p, p.name) for p in vectors]
    cmds = [[VB/'xvlog.bat','--sv',*rtl,testbench]]
    for top in ['tb_legacy','tb_tuned','tb_quality_vga']:
        cmds += [[VB/'xelab.bat',top,'-s',top,'--debug','typical','-mt','2'],[VB/'xsim.bat',top,'-runall']]
missing=[str(p) for p in files if not p.is_file()]
if missing:raise SystemExit('Missing package files: '+repr(missing))
print(json.dumps({'stage':v.stage,'execute':v.execute,'cwd':str(OUT),'required_files_checked':len(files),'commands':[[str(x) for x in c] for c in cmds]},ensure_ascii=True,indent=2))
if not v.execute:raise SystemExit(0)
for cmd in cmds:
 if not Path(cmd[0]).is_file():raise SystemExit('Tool not found: '+str(cmd[0]))
OUT.mkdir(parents=True,exist_ok=False)
for p,name in copies:shutil.copy2(p,OUT/name)
env=os.environ.copy();env['XILINX_LOCAL_USER_DATA']='no'
for i,cmd in enumerate(cmds):
 with (OUT/f'stage_{i}.log').open('x',encoding='utf8') as log:rc=subprocess.run([str(x) for x in cmd],cwd=OUT,env=env,stdout=log,stderr=subprocess.STDOUT).returncode
 if rc:raise SystemExit(f'Failed stage {i}, exit={rc}; logs retained in {OUT}')
print('Offline commands completed; inspect validation logs. No hardware tested.')
