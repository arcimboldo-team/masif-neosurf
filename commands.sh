



change-db(){
	if [[ -n "$1" ]]; then
		export DB_NAME="$1"
	elif [[ -n "$DB_NAME" ]]; then
		export DB_NAME="$DB_NAME"
	else
		export DB_NAME="example"
	fi

	echo -e " * Using $DB_NAME db\033]0;$DB_NAME DB\a"
	export DB_FOLDER="./DBs/$DB_NAME-db"
	export DB_PDB_FOLDER="$DB_FOLDER/pdbs"
	export DB_PROCESSED_FOLDER="$DB_FOLDER/processed"
	export DB_RESULTS_FOLDER="$DB_FOLDER/search_results"
	mkdir -p $DB_PDB_FOLDER
}
change-db

build (){
	sudo docker build . -t masif-neosurf
}

run (){
	echo "$(sudo docker ps -a | grep "masif-neosurf")"
	if [[ -z "$(sudo docker ps | grep "masif-neosurf")" ]]; then
		if [[ -z "$(sudo docker ps -a | grep "masif-neosurf")" ]]; then
			echo " * Creating new Docker container..."
			new
		else
			echo " * Starting up existing container..."
			sudo docker start -ia $(sudo docker ps -a |grep "masif-neosurf"|head -1|cut -d " " -f1 )
		fi
	else
		echo " * Connecting to running Docker container..."
		connect
	fi
}

connect (){
	sudo docker exec -it $(sudo docker ps |grep "masif-neosurf"|head -1|rev|cut -d " " -f1 |rev) bash
}

stop (){
	sudo docker stop $(sudo docker ps |grep "masif-neosurf"|head -1|cut -d " " -f1 ) || echo "No running container"
}

new (){
	sudo docker run -it -v $PWD:/home/masif-neosurf -u neosurfer --runtime runc masif-neosurf
}

new-gpu (){
	sudo docker run -it -v $PWD:/home/masif-neosurf -u neosurfer --runtime=nvidia --gpus all masif-neosurf
}


clean (){
	sudo docker rm $(sudo docker ps --filter status=exited -q)
}

check-neosurfer() {
	if [[ $(whoami) == "neosurfer" ]]; then
		echo "Neosurfing"
		return 0
	else
		echo "NOT neosurfing"
		return 1
	fi
}

process-list (){
	check-neosurfer || return 1
	path=$(realpath $1)
	echo "Processing CODES in : $path"

	declare -a codes=()
	while read line; do
		echo $line
		process-pdb $line
	done < $path
}

process-pdb (){
	check-neosurfer || return 1
	CODE=$1
	FNAME="$1.pdb"
	CHAIN="$2"
	mkdir -p $DB_PDB_FOLDER
	FILEPATH="$DB_PDB_FOLDER/$FNAME"



	if ! [[ -f "$FILEPATH" ]]; then
		curl https://files.rcsb.org/download/${CODE}.pdb -o "$FILEPATH" || return 1
	fi

	if [[ -z "$CHAIN" ]]; then
		echo "Processing ${CODE} (all chains)"
		declare -a chains=()
		while read -r line; do
			line=$(echo $line | tr -s ' ')
			#echo $line
			if [[ $(echo $line | cut -d " " -f1 ) == "ATOM" ]]; then
				chain="$(echo $line | cut -d " " -f5)"
				chain="${chain::1}"
				#echo "$line $chain"
				chain_added="0"
				#echo "${chains[@]}"

				#echo $(echo "${chains[@]}" | grep -c "$chain")
				#echo $([[ $(echo "${chains[@]}" | grep -c "$chain") -gt 0 ]])

				if [[ $(echo "${chains[@]}" | grep -c "$chain") -eq 0 ]]; then
					echo "- Detected new chain: $chain"
					chains+=("$chain")
				fi

			fi
		done < <(grep 'ATOM ' $FILEPATH | grep "CA")
	else
		echo "Processing ${CODE}_${CHAIN}"
		declare -a chains=("$CHAIN")
	fi
	for chain in ${chains[@]}; do
		echo "$DB_PROCESSED_FOLDER/descriptors/sc05/all_feat/${CODE}_${chain}"
		if [[ -d $DB_PROCESSED_FOLDER/descriptors/sc05/all_feat/${CODE}_${chain} ]]; then
			echo " * PDB (${CODE}_${chain}) already processed"
		else
			echo " * Processing $FILEPATH ${CODE}_${chain}"
			python -W ignore ./preprocess_pdb.py $FILEPATH ${CODE}_${chain} -o $DB_PROCESSED_FOLDER
		fi

	done
}



search (){

	if [[ $# -lt 3 ]]; then
		echo "Please provide <pdb code> <chain> <num_sites>"
		return 1
	fi
	CODE=$1
	CHAIN=$2
	NUM_SITES=$3
	echo " * Filtering vertices..."
	python ./filter_vertices.py $DB_PROCESSED_FOLDER/output/all_feat_3l/pred_surfaces/$1_$2.ply $NUM_SITES
	echo ""
	echo " * Searching targets for $1_$2 in $DB_PROCESSED_FOLDER"
	VERTICE_PATH="$DB_PROCESSED_FOLDER/output/all_feat_3l/pred_surfaces/$1_$2.filtered_$3.vix"
	if [[ -f "$VERTICE_PATH" ]]; then

		echo " * Using filtered vertices from $VERTICE_PATH"
		python -W ignore masif_search.py \
		--target_dir $DB_PROCESSED_FOLDER \
		--target ${CODE}_${CHAIN} \
		--database $DB_PROCESSED_FOLDER \
		--out_dir "$DB_RESULTS_FOLDER/$NUM_SITES" \
		--site_vix_file="$VERTICE_PATH" "${@:3:}"
	else
		echo " * Filtered file: $VERTICE_PATH not found"
		echo " * Using highest scoring vertices"
		python -W ignore masif_search.py \
		--target_dir $DB_PROCESSED_FOLDER \
		--target ${CODE}_${CHAIN} \
		--database $DB_PROCESSED_FOLDER \
		--out_dir "$DB_RESULTS_FOLDER/$NUM_SITES" \
		--num_sites  $NUM_SITES "${@:3:}"
	fi
	return 1




	echo " * Results saved to $DB_RESULTS_FOLDER"
}



show (){

	echo " * Showing search results"
	python ./search_show.py "$@"
}


install-nvidia (){
	# Setup nvidia drivers
	sudo apt-get update && sudo apt-get install -y --no-install-recommends ca-certificates curl gnupg2

	curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg \
		&& curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
		sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
	sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

	sudo apt-get update

	export NVIDIA_CONTAINER_TOOLKIT_VERSION=1.20.1-1
	sudo apt-get install -y \
		nvidia-container-toolkit=${NVIDIA_CONTAINER_TOOLKIT_VERSION} \
		nvidia-container-toolkit-base=${NVIDIA_CONTAINER_TOOLKIT_VERSION} \
		libnvidia-container-tools=${NVIDIA_CONTAINER_TOOLKIT_VERSION} \
		libnvidia-container1=${NVIDIA_CONTAINER_TOOLKIT_VERSION}

	sudo nvidia-ctk config --in-place \
		--set nvidia-container-runtime.log-level=debug

	sudo nvidia-ctk runtime configure --runtime=docker
	sudo systemctl restart docker
}