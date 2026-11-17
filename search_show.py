import sys, os, bioiain, json, shutil, glob

from bioiain.visualisation.pymol import PymolScript
from bioiain.utilities import relative_path
import numpy as np

results_folder=os.environ["DB_RESULTS_FOLDER"]
N_BEST = None
if "--best" in sys.argv:
    N_BEST = int(sys.argv[sys.argv.index("--best") + 1])

I = None
if "-i" in sys.argv:
    I = int(sys.argv[sys.argv.index("-i") + 1])

REPRESENTATIVE = "--representative" in sys.argv

if len(os.listdir(results_folder)) == 1:
    results_folder=os.path.join(results_folder, os.listdir(results_folder)[0])

elif len(os.listdir(results_folder)) == 0:
    print(" * No results found in:", results_folder)
else:
    print(" * Multiple results found:")
    folders = [f for f in os.listdir(results_folder) if os.path.isdir(os.path.join(results_folder, f))]
    for n, folder in enumerate(folders):
        print(f"[{n}]: {folder}")
    fn = None
    while fn is None:
        try:
            if I is not None:
                fn = I
                I = None
            else:
                fn = int(input(" * Please select desired folder (int):\n>>> "))
        except ValueError:
            print("Please introduce an int")
            fn = None
    results_folder = os.path.join(results_folder, folders[fn])



print(" *  Results folder:", results_folder)



target_name = sys.argv[1]
print(" * Target name:", target_name)
target_folder=os.path.join(results_folder, target_name)
print(" * Target folder:", target_folder)
assert os.path.exists(target_folder)

sites = []
for site in os.listdir(target_folder):
    site_path = os.path.join(target_folder, site)
    if os.path.isdir(site_path):
        sites.append(site)

sites = sorted(sites)
print("N Sites:", len(sites))

script_name=f"search_{target_name}_{folders[fn]}"
script = PymolScript(script_name, pymol_path="/usr/bin/pymol")
script.raw(f"import numpy as np")
print(script)

pdb_path = os.path.join(target_folder, target_name+".pdb")
ply_path = os.path.join(target_folder, target_name+".ply")

selected_sites_path = os.path.join(target_folder, f"selected_sites.vert")
script.raw(f"cd {os.path.abspath(os.getcwd())}")
script.raw(f"cd {script.subfolder}")



output_folder = os.path.join("./output", folders[fn], target_name)
os.makedirs(output_folder, exist_ok=True)

score_file = os.path.join(output_folder, f"scores.tsv")



script.load(pdb_path)
script.raw(f"loadply {relative_path(ply_path, script.subfolder)}")
scores = {}
for site in sites:
    site_path = os.path.join(target_folder, site)
    n_in_site=0
    for match in os.listdir(site_path):
        match_path=os.path.join(site_path, match)
        if not os.path.isdir(match_path):
            continue
        name = f"{site}_{match}"

        for file in os.listdir(match_path):
            if file.endswith(".pdb"):
                path = os.path.join(match_path, file)
            elif file.endswith(".npy"):
                matrix = f"matrix_{name}"
                script.raw(f"{matrix} = np.load('{relative_path(os.path.join(match_path, file), script.subfolder)}').flatten()")
            elif file.endswith(".score"):
                with open(os.path.join(match_path, file), "r") as f:
                    score = {s.split(":")[0].strip():s.split(":")[1].strip() for s in f.read().split(",")}
                    scores[name] = score
        script.load(path, name)
        #script.disable(name)
        n_in_site += 1
        #script.raw(f"cmd.transform_object('{name}', {matrix})")
    if n_in_site > 0:
        script.group(site)
        script.disable(site)
#print(scores)
scores = {k:v for k, v in sorted(scores.items(), key=lambda x: float(x[1]["score"]), reverse = True)}

if REPRESENTATIVE:
    json.dump(scores, open(score_file, "w"), indent=4)
# with open(score_file, "w") as f:
#     for k, v in scores.items():
#         f.write(f"{k}\t{v}")


if N_BEST is not None:
    for name, data in scores.items():
        script.disable(name)
        script.disable("_".join(name.split("_")[:2]))
    scores = {k:v for k, v in list(scores.items())[:N_BEST]}
    print(json.dumps(scores, indent=4))
    for name, data in scores.items():
        script.enable(name)
        script.enable("_".join(name.split("_")[:2]))

script.disable("vert*")
script.disable("pb*")
script.disable("hbond*")
script.disable("mesh*")
script.disable("hphobic*")
with open(selected_sites_path) as f:
    for n, line in enumerate(f):
        #print(n)
        coord_str = [c.strip() for c in line.split(",")]
        coord = [float(x) for x in coord_str]
        b=0
        with open(ply_path) as ply:
            for vert in ply:
                #print(vert)
                #print([float(c) % 1 for c in coord_str])
                cc =" ".join([c if (float(c) % 1 != 0) else str(int(float(c))) for c in coord_str])
                #print(cc)
                if vert.startswith(cc):
                    data = vert.split(" ")
                    #print(data)
                    b = data[3]
                    #print(b)
                    break
        script.pseudoatom(f"sites{n}", coord=coord, elem="'ca'", b=b) #Will be patched in 0.3.5




script.group("sites", "sites")
script.show("sites", "spheres")
script.orient()
script.spectrum("sites", minimum=0, maximum=1)
if "--pymol" in sys.argv:
    script.execute(extra_options=None, quiet=True)
elif "--compile" in sys.argv:
    script.compile(extra_options=None, quiet=True, use_compiled=False, keep_compiler=True, batch_mode=False)
    if REPRESENTATIVE:
        css = glob.glob(f"./bioiain.d/pml_sessions/{script_name}/*.session.pse", recursive=True)
        print(css)
        if len(css) == 1:
            shutil.copy(css[0], output_folder)

else:
    script.save()








