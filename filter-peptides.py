import sys, os, bioiain, glob, subprocess

from bioiain import log

path = sys.argv[1]
out_path = path.replace(".list", ".chain.list")
DB_NAME = os.environ.get("DB_NAME", "example")
#codes = sorted(open(path).read().replace("\n", ",").split(","))
dataset = bioiain.utilities.files.StructureDataset.from_list(path, name=DB_NAME)

log("header", dataset)

with open(out_path, "w") as f:
    for entry in dataset:
        entity = entry.entity()
        log(1, entity)
        print(entity.chains())
        all_chains = [chain.complex() for chain in entity.chains()]
        entity = entity.clean_and_long()
        print(entity.chains())

        for chain in entity.chains():
            print(f"{chain.code()}_{chain.complex()}")
            f.write(f"{chain.code()}_{chain.complex()}\n")
            all_chains.remove(chain.complex())

        print(f"Remaining chains: {all_chains}")
        for peptide_chain in all_chains:
            glob_path = f"./DBs/{DB_NAME}-db/**/{entity.code()}_{peptide_chain}/"
            print(glob_path)
            peptide_paths = glob.glob(glob_path, recursive=True)
            print(peptide_paths)
            for folder in peptide_paths:

                print(f"Removing folder:", folder)
                print(f"$ sudo rm -r {folder}")
                subprocess.run(f"sudo rm -r {folder}", shell=True, check=True)