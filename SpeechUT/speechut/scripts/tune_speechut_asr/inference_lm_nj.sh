#####################################
# SpeechUT ASR model #
#####################################
[ $# -lt 2 ] && echo "Usage: $0 <model_path> <data_dir> [gen-set=dev_other] [beam_size=30] [ctc_weight=0.2] [lm_weight=0.7] [lm_path] [nj=8] [ngpu=8]" && exit 1
[ ${PWD##*/} != SpeechUT ] && echo "Error: dir not match! Switch to SpeechUT/ and run it again!" && exit 1

model_path=$1
DATA_DIR=$2
gen_set=$3
beam_size=$4
ctc_weight=$5
lm_weight=$6
lm_path=$7
nj=$8
ngpu=$9
[ -z $gen_set ] && gen_set="dev_other"
[ -z $beam_size ] && beam_size=30
[ -z $ctc_weight ] && ctc_weight=0.3
[ -z $lm_weight ] && lm_weight=0.7
[ -z $lm_path ] && lm_path="/mnt/default/v-junyiao/librispeech/lm/lm_ctc_form/checkpoint_best.pt"
[ $ctc_weight == 0 ] && [ $beam_size != 1 ] && echo "Change beam size to 1 and lm_weight to 0 as no ctc-decoding used..." && beam_size=1 && lm_weight=0
[ $ctc_weight != 0 ] && extra="--batch-size 1"
[ -z $nj ] && nj=8
[ -z $ngpu ] && ngpu=8

src_dir=${model_path%/*}
cpt=${model_path##*/}
cpt=${cpt%.*}

CODE_ROOT=${PWD}

world_size=$nj
for rank in $(seq 0 $((nj - 1))); do
    export CUDA_VISIBLE_DEVICES=$((rank % $ngpu))
    for subset in ${gen_set//,/ }; do
        results_path=$src_dir/decode_${cpt}/beam${beam_size}_ctc${ctc_weight}_lm${lm_weight}/${subset}_${world_size}_${rank}
        [ ! -d $results_path ] && mkdir -p $results_path

        python $CODE_ROOT/fairseq/fairseq_cli/generate.py $DATA_DIR \
        --user-dir $CODE_ROOT/speechut \
        --label-dir ${DATA_DIR} \
        --labels '["ltr"]' \
        --single-target \
        --post-process letter \
        --gen-subset ${subset} \
        --max-tokens 800000 \
        \
        --task joint_sc2t_pretraining \
        --add-decoder-target \
        --fine-tuning \
        --pad-audio \
        --random-crop \
        \
        --ctc-weight ${ctc_weight} $extra \
        --lm-weight ${lm_weight} --lm-path ${lm_path} \
        --beam ${beam_size} \
        \
        --path ${model_path} \
        --results-path $results_path \
        \
        --scoring wer --max-len-a 0.00078125 --max-len-b 200 \
        --distributed-world-size ${world_size} --distributed-rank ${rank} \
        &
    done
done
wait


for subset in ${gen_set//,/ }; do
    results_dir=$src_dir/decode_${cpt}/beam${beam_size}_ctc${ctc_weight}_lm${lm_weight}
    cat $results_dir/${subset}_${world_size}_*/generate-${subset}.txt | grep -v "^Generate" > $results_dir/generate-${subset}.all.txt
done