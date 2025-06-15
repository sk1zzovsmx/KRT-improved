#!/usr/bin/env python3
import sys, glob, re


def parse_config(path):
    cfg = {}
    with open(path, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            if '=' not in line:
                continue
            key, value = line.split('=', 1)
            key = key.strip()
            value = value.strip().strip('"').strip("'")
            if value.lower() in ('true', 'false'):
                cfg[key] = value.lower() == 'true'
            else:
                try:
                    cfg[key] = int(value)
                except ValueError:
                    cfg[key] = value
    return cfg


def format_file(path, cfg):
    with open(path, 'rb') as f:
        data = f.read()
    has_final_nl = data.endswith(b'\n')
    text = data.decode('utf-8').replace('\r\n', '\n').replace('\r', '\n')
    lines = text.split('\n')
    indent_width = int(cfg.get('indent_width', 4))
    indent_type = cfg.get('indent_type', 'Tabs')
    formatted = []
    for line in lines:
        stripped = line.rstrip()
        if indent_type.lower() == 'tabs':
            match = re.match(r'^[ ]+', stripped)
            if match:
                spaces = len(match.group(0))
                tab_count = spaces // indent_width
                extra_spaces = spaces % indent_width
                stripped = '\t' * tab_count + ' ' * extra_spaces + stripped[spaces:]
        formatted.append(stripped)
    out_text = '\n'.join(formatted)
    if has_final_nl:
        out_bytes = (out_text + '\n').encode('utf-8')
    else:
        out_bytes = out_text.encode('utf-8')
    if out_bytes != data:
        with open(path, 'wb') as f:
            f.write(out_bytes)


def main():
    args = sys.argv[1:]
    cfg_path = None
    pattern = None
    i = 0
    while i < len(args):
        if args[i] == '--config-path':
            cfg_path = args[i+1]
            i += 2
        else:
            pattern = args[i]
            i += 1
    if not cfg_path or not pattern:
        print('Usage: stylua --config-path <path> <pattern>')
        return 1
    cfg = parse_config(cfg_path)
    for file in glob.glob(pattern):
        format_file(file, cfg)
    return 0

if __name__ == '__main__':
    sys.exit(main())
