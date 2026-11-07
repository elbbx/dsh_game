#!/usr/bin/env python3
"""Optional bounded, explicit, local loop for a user-installed CLI coding agent.

Does not include/activate an AI model. It never runs unless the user manually invokes it.
Pass the agent executable and arguments after '--'; it feeds the documented prompt to stdin.
"""
from pathlib import Path
import argparse,subprocess,sys,json,datetime,hashlib

def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest() if path.exists() else ''

def run():
    ap=argparse.ArgumentParser(description='Explicit opt-in loop; one main working tree; finite cycles.')
    ap.add_argument('--root',default='.',help='Unzipped project root')
    ap.add_argument('--cycles',type=int,default=1,help='Max number of AI invocations, 1 to 20')
    ap.add_argument('--timeout-sec',type=int,default=1800,help='Per-invocation timeout')
    ap.add_argument('--dry-run',action='store_true')
    ap.add_argument('agent_command',nargs=argparse.REMAINDER,help='After --, CLI and arguments; must accept prompt on stdin')
    args=ap.parse_args()
    root=Path(args.root).resolve()
    command=args.agent_command[:]
    if command and command[0]=='--':command.pop(0)
    if not 1<=args.cycles<=20:ap.error('--cycles must be 1..20')
    if args.timeout_sec<60 or args.timeout_sec>14400:ap.error('--timeout-sec must be 60..14400')
    for path in ['AGENTS.md','ai/直接复制给AI的启动指令.md','ai/恢复继续.md','finished/state.json']:
        if not (root/path).exists():ap.error('missing project file: '+path)
    if not command:ap.error('provide user-installed agent command after -- (e.g. -- codex exec -)')
    print('PROJECT:',root,'\nAGENT COMMAND:',repr(command),'\nCYCLES:',args.cycles)
    print('The CLI may incur fees and request permissions. Review its own security and billing settings.')
    if args.dry_run:
        print('DRY-RUN: No AI invoked and no code modified.')
        return 0
    reports=root/'finished/reports';reports.mkdir(parents=True,exist_ok=True)
    state=root/'finished/state.json'
    for index in range(args.cycles):
        before=sha256(state)
        prompt=(root/('ai/直接复制给AI的启动指令.md' if index==0 else 'ai/恢复继续.md')).read_text('utf8')
        prompt+='\n\nYour execution is one bounded iteration of a persistent single-agent workspace. Continue autonomously without seeking per-feature handoff; update finished/state.json after QA.\n'
        now=datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
        log=reports/f'agent_run_{now}_cycle{index+1:02d}.log'
        try:
            result=subprocess.run(command,input=prompt,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,cwd=root,timeout=args.timeout_sec)
        except (subprocess.TimeoutExpired, OSError) as exc:
            log.write_text('ERROR: '+repr(exc)+'\n',encoding='utf8')
            print('Agent invocation failed; stopping:',repr(exc));return 2
        log.write_text(result.stdout,encoding='utf8')
        print('cycle',index+1,'agent_exit',result.returncode,'output',log)
        if result.returncode != 0:
            print('Agent returned nonzero; stopping to avoid runaway retries.');return 3
        qa=subprocess.run([sys.executable,str(root/'scripts/qa_cycle.py'),'--root',str(root)],capture_output=True,text=True,cwd=root)
        print(qa.stdout)
        if qa.returncode != 0:
            print('QA failed; require agent repair before further automated cycles.');return 4
        newstate=json.loads(state.read_text('utf8'))
        if sha256(state)==before:
            print('finished/state.json unchanged; stopping rather than issuing unbounded repeat prompts.');return 5
        if newstate.get('release_status')=='shippable':
            print('Agent reports shippable. Verify exported build and audit independently.');return 0
        if newstate.get('blocked_on'):
            print('Agent recorded blockers. Stopping; human review may be required.');return 6
    print('Reached configured cycle budget. Run again explicitly if further development is desired.')
    return 0

if __name__=='__main__':sys.exit(run())
