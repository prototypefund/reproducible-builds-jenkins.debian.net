#!/usr/bin/env python3
# -*- coding: utf-8 -*-
#
# Copyright © 2019 Paul Spooren <mail@aparcar.org>
#
# Inspired by reproducible_common.sh
#   © Holger Levsen <holger@layer-acht.org>
#
# Released under the GPLv2

import os
import subprocess
import resource


def e(var, default):
    """Return env variable or default"""
    return os.environ.get(var, default)


# DBSUITE which version of diffoscope to use
timeout = e("TIMEOUT", 30 * 60)  # 30m
# DIFFOSCOPE_VIRT_LIMIT max RAM usage
ds_virt_limit = int(e("DIFFOSCOPE_VIRT_LIMIT", 10 * 1024 ** 3))  # 10GB
# TIMEOUT timeout for diffoscope in seconds
dbsuite = e("DBDSUITE", "unstable")
# SCHROOT to use
schroot = e("SCHROOT", f"source:jenkins-reproducible-{dbsuite}-diffoscope")


def limit_resources():
    resource.setrlimit(resource.RLIMIT_CPU, (1, 1))
    resource.setrlimit(resource.RLIMIT_AS, (ds_virt_limit, resource.RLIM_INFINITY))


def diffoscope_version():
    cmd = []
    if schroot:
        cmd.extend(["schroot", "--directory", "/tmp", "-c", schroot])

    cmd.extend(["diffoscope", "--", "--version"])
    print(cmd)
    return (
        subprocess.run(cmd, capture_output=True, text=True, preexec_fn=limit_resources)
        .stdout.strip()
        .split()[1]
    )


def diffoscope_compare(path_a, path_b, path_output_html):
    """
    Run diffoscope in a schroot environment

    Args:
    - path_a path to first file to compare
    - path_b path to second file a to compare
    - path_output_html path where to store result html
    """
    cmd = []
    if schroot:
        cmd.extend(
            ["schroot", "--directory", os.path.dirname(path_output_html), "-c", schroot]
        )

    try:
        cmd.extend(["diffoscope", "--", "--html", path_output_html, path_a, path_b])
        result = subprocess.run(
            cmd,
            timeout=timeout,
            capture_output=True,
            text=True,
            preexec_fn=limit_resources,
        )
        msg = f"diffoscope {diffoscope_version()} "
        if result.returncode == 0:
            print(msg + f"{path_a} reproducible, yay!")
        else:
            if result.returncode == 1:
                print(msg + f"found issues, please investigate {path_a}")
            elif result.returncode == 2:
                with open(path_output_html, "w") as output_html_file:
                    output_html_file.write(
                        msg
                        + f"""had trouble comparing the two builds. Please
                                investigate {path_a}"""
                    )

    except subprocess.TimeoutExpired:
        if os.path.exists(path_output_html):
            print(
                msg
                + f"""produced no output comparing {path_a} with {path_b} and
                    was killed after running into timeout after {timeout}..."""
            )
        else:
            print(
                msg
                + """was killed after running into timeout after $TIMEOUT, but
                    there is still {path_output_html}"""
            )
