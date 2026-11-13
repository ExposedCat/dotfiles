#!/usr/bin/env python3
"""Write a dialog decision, or run Hyprland's custom source picker."""
import argparse
import json
import os
from pathlib import Path
import sys

from common import Dialog, atomic_json, share_result, share_sources, workspace_previews


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('respond', 'share', 'preview'))
    parser.add_argument('args', nargs='*')
    args = parser.parse_args()
    if args.action == 'respond':
        directory, payload = args.args
        result = json.loads(payload)
        if type(result.get('response')) is not int or result['response'] not in (0, 1, 2):
            raise ValueError('Invalid response')
        atomic_json(Path(directory) / 'response.json', result)
        return
    if args.action == 'preview':
        data = json.loads(Path(args.args[0]).read_text())
    else:
        sources = workspace_previews(share_sources(os.environ))
        data = {'kind': 'share', 'title': 'Choose what to share', 'app': {'name': 'Screen sharing'},
                'outputs': sources[0], 'windows': sources[1], 'workspaces': sources[2],
                'remember': '--allow-token' in args.args}
    dialog = Dialog(data)
    try:
        dialog.process.wait()
        result = dialog.result()
        if args.action == 'preview':
            print(json.dumps(result))
        else:
            selection = share_result(result, sources)
            if selection:
                print(selection, flush=True)
    finally:
        dialog.close()


if __name__ == '__main__':
    # XDPH passes --allow-token; keep it as picker data, not an argparse option.
    if len(sys.argv) > 1 and sys.argv[1] == 'share':
        sys.argv.insert(2, '--')
    try:
        main()
    except (OSError, ValueError, KeyError) as error:
        print(f'Desktop portal: {error}', file=sys.stderr)
        raise SystemExit(1)
