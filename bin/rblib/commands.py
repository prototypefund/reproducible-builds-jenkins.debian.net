# -*- coding: utf-8 -*-
#
# Copyright © 2015-2019 Mattia Rizzolo <mattia@debian.org>
# Copyright © 2015-2017 Holger Levsen <holger@layer-acht.org>
# Copyright © 2019      Paul Spooren <mail@aparcar.org>
#
# Licensed under GPL-2

import os
import subprocess
import resource


class Schroot():
    def __init__(self, chroot, directory=None):
        self.chroot = chroot
        self._cmd = ['schroot', '-c', chroot]
        self.set_directory(directory)
        self._limits = []

    def set_directory(self, directory):
        if not directory:
            self.directory = '/tmp'
        self._cmd.extend(('--directory', self.directory))

    def add_limit(self, what, how):
        self._limits.append((what, how))

    def set_default_limits(self):
        # 10 GB of actually used memory
        self._limits.append(
            resource.RLIMIT_AS, (10 * 1024 ** 3, resource.RLIM_INFINITY)
        )

    def _preexec_limiter(self):
        for limit in self._limits:
            resource.setrlimit(*limit)

    def run(self, command, *, check=False, timeout=False):
        # separate the command name frome the optiosn with --
        self._cmd.append(command[0])
        self._cmd.append('--')
        self._cmd.extend(command[1:])
        return subprocess.run(
            self._cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            check=check,
            timeout=timeout,
            text=check,
            preexec_fn=self._preexec_limiter,
        )


class Diffoscope(Schroot):
    def __init__(self, chroot=None, suite=None):
        if suite is None:
            suite = 'unstable'
        if chroot is None:
            chroot = f'jenkins-reproducible-{suite}-diffoscope'
        super.__init__(chroot=chroot)
        self.set_default_limits()

    def version(self):
        try:
            p = self.run(('diffoscope', '--version'), check=True)
        except subprocess.CalledProcessError:
            return 'cannot get version'
        return p.stdout.strip()

    def compare_files(self, a, b, html):
        self.set_directory(os.path.dirname(html))
        diff_cmd = ['diffoscope', '--html', html]
        msg = f'diffoscope {self.version()}'
        timeout = 30*60  # 30 minutes
        try:
            p = self.run(diff_cmd + (a, b), timeout=timeout)
            if p.returncode == 0:
                print(f'{msg}: {a} is reproducible, yay!')
            elif p.returncode == 1:
                print(f'{msg}: {a} has issue, please investigate')
            elif p.returncode == 2:
                with open(html, 'w') as f:
                    f.write(f'{msg} had errors comparing the two builds.\n')
                    f.write(f'{diff_cmd}\n')
                    f.write(p.stdout)
        except subprocess.TimeoutExpired:
            if os.path.exits(html):
                text = (f'{msg} produced not output and was killed after '
                        f'running into timeout after {timeout}.')
                with open(html, 'w') as f:
                    f.write(f'text\n')
                    f.write(f'{diff_cmd}\n')
                    f.write(p.stdout)
                print(text)
            else:
                print(f'{msg} was killed after running into timeout after '
                      f'{timeout}, but there still {html}')
