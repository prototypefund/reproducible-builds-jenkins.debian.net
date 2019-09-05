#!/usr/bin/env python3

import os
import re
import pystache
import subprocess
import hashlib
from urllib.request import urlopen
from tempfile import mkdtemp, NamedTemporaryFile
from multiprocessing import cpu_count
from multiprocessing import Pool
from time import strftime, gmtime
import shutil
import importlib

# target to be build
target = os.environ.get("TARGET", "ath79/generic")
# version to be build
version = os.environ.get("VERSION", "SNAPSHOT")
# where to store rendered html and diffoscope output
output_dir = os.environ.get("OUTPUT_DIR", "/srv/reproducible-results")
# where to (re)build openwrt
temporary_dir = os.environ.get("TMP_DIR", mkdtemp(dir="/srv/workspace/chroots/"))
# where to find mustache templates
template_dir = os.environ.get(
    "TEMPLATE_DIR", "/srv/jenkins/mustache-templates/reproducible"
)
# where to find the origin builds
openwrt_url = (
    os.environ.get("ORIGIN_URL", "https://downloads.openwrt.org/snapshots/targets/")
    + target
)

# dir of the version + target
target_dir = os.path.join(output_dir, version, target)
# dir where openwrt actually stores binary files
rebuild_dir = temporary_dir + "/bin/targets/" + target
# where to get the openwrt source git
openwrt_git = os.environ.get("OPENWRT_GIT", "https://github.com/openwrt/openwrt.git")

# run a command in shell
def run_command(cmd, cwd=".", ignore_errors=False):
    print("Running {} in {}".format(cmd, cwd))
    proc = subprocess.Popen(cmd, cwd=cwd, stdout=subprocess.PIPE)
    response = ""
    # print and store the output at the same time
    while True:
        line = proc.stdout.readline().decode("utf-8")
        if line == "" and proc.poll() != None:
            break
        response += line
        print(line, end="", flush=True)

    if proc.returncode and not ignore_errors:
        print("Error running {}".format(cmd))
        quit()
    return response


# files not to check via diffoscope
meta_files = re.compile(
    "|".join(
        [
            ".+\.buildinfo",
            ".+\.manifest",
            "openwrt-imagebuilder",
            "openwrt-sdk",
            "sha256sums",
            "kernel-debug.tar.bz2",
        ]
    )
)

# the context to fill the mustache tempaltes
context = {
    "targets": [
        {"version": "SNAPSHOT", "name": "ath79/generic"},
        {"version": "SNAPSHOT", "name": "x86/64"},
        {"version": "SNAPSHOT", "name": "ramips/mt7621"},
    ],
    "version": version,
    "commit_string": "",
    "images_repro": 0,
    "images_repro_percent": 0,
    "images_total": 0,
    "packages_repro": 0,
    "packages_repro_percent": 0,
    "packages_total": 0,
    "today": strftime("%Y-%m-%d", gmtime()),
    "diffoscope_version": run_command(["diffoscope", "--version"]).split()[1],
    "target": target,
    "images": [],
    "packages": [],
    "git_log_oneline": "",
    "missing": [],
}

# download file from openwrt server and compare it, store output in target_dir
def diffoscope(origin_name):
    file_origin = NamedTemporaryFile()

    if get_file(openwrt_url + "/" + origin_name, file_origin.name):
        print("Error downloading {}".format(origin_name))
        return

    run_command(
        [
            "diffoscope",
            file_origin.name,
            rebuild_dir + "/" + origin_name,
            "--html",
            target_dir + "/" + origin_name + ".html",
        ],
        ignore_errors=True,
    )
    file_origin.close()

# return sha256sum of given path
def sha256sum(path):
    with open(path, "rb") as hash_file:
        return hashlib.sha256(hash_file.read()).hexdigest()


# return content of online file or stores it locally if path is given
def get_file(url, path=None):
    print("downloading {}".format(url))
    try:
        content = urlopen(url).read()
    except:
        return 1

    if path:
        print("storing to {}".format(path))
        with open(path, "wb") as file_b:
            file_b.write(content)
        return 0
    else:
        return content.decode("utf-8")

# parse the origin sha256sums file from openwrt
def parse_origin_sha256sums():
    sha256sums = get_file(openwrt_url + "/sha256sums")
    return re.findall(r"(.+?) \*(.+?)\n", sha256sums)


# not required for now
# def exchange_signature(origin_path, rebuild_path):
#    file_sig = NamedTemporaryFile()
#    # extract original signatur in temporary file
#    run_command(
#        "./staging_dir/host/bin/fwtool -s {} {}".format(file_sig.name, origin_path),
#        temporary_dir,
#    )
#    # remove random signatur of rebuild
#    run_command(
#        "./staging_dir/host/bin/fwtool -t -s /dev/null {}".format(rebuild_path),
#        temporary_dir,
#    )
#    # add original signature to rebuild file
#    run_command(
#        "./staging_dir/host/bin/fwtool -S {} {}".format(file_sig.name, rebuild_path),
#        temporary_dir,
#    )
#    file_sig.close()


# initial clone of openwrt.git
run_command(["git", "clone", openwrt_git, temporary_dir])

# download buildinfo files
get_file(openwrt_url + "/config.buildinfo", temporary_dir + "/.config")
with open(temporary_dir + "/.config", "a") as config_file:
    # extra options used by the buildbot
    config_file.writelines(
        [
            "CONFIG_CLEAN_IPKG=y\n",
            "CONFIG_TARGET_ROOTFS_TARGZ=y\n",
            "CONFIG_CLEAN_IPKG=y\n",
            'CONFIG_KERNEL_BUILD_USER="builder"\n',
            'CONFIG_KERNEL_BUILD_DOMAIN="buildhost"\n',
        ]
    )

# insecure private key to build the images
with open(temporary_dir + "/key-build", "w") as key_build_file:
    key_build_file.write(
        "Local build key\nRWRCSwAAAAB12EzgExgKPrR4LMduadFAw1Z8teYQAbg/EgKaN9SUNrgteVb81/bjFcvfnKF7jS1WU8cDdT2VjWE4Cp4cxoxJNrZoBnlXI+ISUeHMbUaFmOzzBR7B9u/LhX3KAmLsrPc="
    )

# spoof the official openwrt public key to prevent adding another key in the binary
with open(temporary_dir + "/key-build.pub", "w") as key_build_pub_file:
    key_build_pub_file.write(
        "OpenWrt snapshot release signature\nRWS1BD5w+adc3j2Hqg9+b66CvLR7NlHbsj7wjNVj0XGt/othDgIAOJS+"
    )
# this specific key is odly chmodded to 600
os.chmod(temporary_dir + "/key-build.pub", 0o600)

# download origin buildinfo file containing the feeds
get_file(openwrt_url + "/feeds.buildinfo", temporary_dir + "/feeds.conf")

# get current commit_string to show in website banner
context["commit_string"] = get_file(openwrt_url + "/version.buildinfo")[:-1]
# ... and parse the actual commit to checkout
commit = context["commit_string"].split("-")[1]

# checkout the desired commit
run_command(["git", "checkout", "-f", commit, temporary_dir])

# show the last 20 commit to have an idea what was changed lately
context["git_log_oneline"] = run_command(
    ["git", "log", "--oneline", "-n", "20"], temporary_dir
)

# do as the buildbots do
run_command(["./scripts/feeds", "update"], temporary_dir)
run_command(["./scripts/feeds", "install", "-a"], temporary_dir)
run_command(["make", "defconfig"], temporary_dir)
# actually build everything
run_command(
    ["make", "IGNORE_ERRORS='n m y'", "BUILD_LOG=1", "-j", str(cpu_count() + 1)],
    temporary_dir,
)

# flush the current website dir of target
shutil.rmtree(target_dir, ignore_errors=True)

# and recreate it here
os.makedirs(target_dir + "/packages", exist_ok=True)

# iterate over all sums in origin sha256sums and check rebuild files
for origin in parse_origin_sha256sums():
    origin_sum, origin_name = origin
    # except the meta files defined above
    if meta_files.match(origin_name):
        print("Skipping meta file {}".format(origin_name))
        continue

    rebuild_path = temporary_dir + "/bin/targets/" + target + "/" + origin_name
    # report missing files
    if not os.path.exists(rebuild_path):
        context["missing"].append({"name": origin_name})
    else:
        rebuild_info = {
            "name": origin_name,
            "size": os.path.getsize(rebuild_path),
            "sha256sum": sha256sum(rebuild_path),
            "repro": False,
        }

        # files ending with ipk are considered packages
        if origin_name.endswith(".ipk"):
            if rebuild_info["sha256sum"] == origin_sum:
                rebuild_info["repro"] = True
                context["packages_repro"] += 1
            context["packages"].append(rebuild_info)
        else:
            #everything else should be images
            if rebuild_info["sha256sum"] == origin_sum:
                rebuild_info["repro"] = True
                context["images_repro"] += 1
            context["images"].append(rebuild_info)

# calculate how many images are reproducible
context["images_total"] = len(context["images"])
if context["images_total"]:
    context["images_repro_percent"] = round(
        context["images_repro"] / context["images_total"] * 100.0, 2
    )

# calculate how many packages are reproducible
context["packages_total"] = len(context["packages"])
if context["packages_total"]:
    context["packages_repro_percent"] = round(
        context["packages_repro"] / context["packages_total"] * 100.0, 2
    )

# now render the website
renderer = pystache.Renderer()
mustache_header = renderer.load_template(template_dir + "/header")
mustache_footer = renderer.load_template(template_dir + "/footer")
mustache_target = renderer.load_template(template_dir + "/target")
mustache_index = renderer.load_template(template_dir + "/index")

index_html = renderer.render(mustache_header, context)
index_html += renderer.render(mustache_index, context)
index_html += renderer.render(mustache_footer, context)

target_html = renderer.render(mustache_header, context)
target_html += renderer.render(mustache_target, context)
target_html += renderer.render(mustache_footer, context)

# and store the files
with open(output_dir + "/index.html", "w") as index_file:
    index_file.write(index_html)

with open(target_dir + "/index.html", "w") as target_file:
    target_file.write(target_html)

# get the origin manifest
origin_manifest = get_file(openwrt_url + "/packages/Packages.manifest")

# and store it in the databse
ropp = importlib.import_module("reproducible_openwrt_package_parser")
with open(rebuild_dir + "/packages/Packages.manifest") as rebuild_manifest:
    result = ropp.show_list_difference(origin_manifest, rebuild_manifest.readlines())
    ropp.insert_into_db(result, "{}-rebuild".format(version))

# run diffoscope over non reproducible files in all available threads
pool = Pool(cpu_count() + 1)
pool.map(
    diffoscope,
    map(
        lambda x: x["name"],
        filter(lambda x: not x["repro"], context["images"] + context["packages"]),
    ),
)

# debug option to keep build dir
if not os.environ.get("KEEP_BUILD_DIR"):
    print("removing build dir")
    shutil.rmtree(temporary_dir)
print("all done")
