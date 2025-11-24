#!/bin/bash
###
 # @Author: Outsider & Gemini
 # @Date: 2025-11-19 16:59:56
 # @LastEditors: Outsider
 # @LastEditTime: 2025-11-20 19:11:12
 # @Description: In User Settings Edit
 # @FilePath: /llocks/client/lock/run.sh
### 

# --- Configuration ---
CLI_SCRIPT="./cli.sh" # Path to your main experiment script
OUTPUT_DIR="./results_$(date +%Y%m%d_%H%M%S)"
DRAW_SCRIPT="./fig.py" # Path to the plotting script

# --- Define Test Cases ---
# Each element in this array is a string defining the variables to override in cli.sh
# Example: "elc=1 lru_resize=1"
# Test Case 1: ELC enabled, LRU resizing enabled

# TEST_CASES[0]="lru_resize=1 lock_reclaim_pol=1 lock_reclaim_batch=512 lock_reclaim_batch_per=1"
# TEST_CASES[1]="lru_resize=0 lock_reclaim_pol=1 lock_reclaim_batch=512 lock_reclaim_batch_per=1"
# TEST_CASES[2]="lru_resize=0 lock_reclaim_pol=1 lock_reclaim_batch=0 lock_reclaim_batch_per=1"
# TEST_CASES[3]="lru_resize=0 lock_reclaim_pol=1 lock_reclaim_batch=0 lock_reclaim_batch_per=3"
# TEST_CASES[4]="lru_resize=0 lock_reclaim_pol=1 lock_reclaim_batch=0 lock_reclaim_batch_per=5"
# TEST_CASES[5]="lru_resize=0 lock_reclaim_pol=1 lock_reclaim_batch=0 lock_reclaim_batch_per=7"
# TEST_CASES[6]="lru_resize=0 lock_reclaim_pol=1 lock_reclaim_batch=0 lock_reclaim_batch_per=10"
# TEST_CASES[7]="lru_resize=0 lock_reclaim_pol=1 lock_reclaim_batch=0 lock_reclaim_batch_per=15"
# TEST_CASES[8]="lru_resize=0 lock_reclaim_pol=0 lock_reclaim_batch=512 lock_reclaim_batch_per=2"
# TEST_CASES[9]="lru_resize=0 lock_reclaim_pol=0 lock_reclaim_batch=0 lock_reclaim_batch_per=2"
# TEST_CASES[10]="lru_resize=1 lock_reclaim_pol=1 lock_reclaim_batch=512 lock_reclaim_batch_per=1"
# TEST_CASES[11]="lru_resize=1 lock_reclaim_pol=1 lock_reclaim_batch=512 lock_reclaim_batch_per=1"
# TEST_CASES[12]="lru_resize=1 lock_reclaim_pol=1 lock_reclaim_batch=512 lock_reclaim_batch_per=1"

# TEST_CASES[13]="lru_resize=0 lock_reclaim_pol=1 lock_reclaim_batch=512 lock_reclaim_batch_per=1"
# TEST_CASES[14]="lru_resize=0 lock_reclaim_pol=1 lock_reclaim_batch=0 lock_reclaim_batch_per=1"
# TEST_CASES[15]="lru_resize=0 lock_reclaim_pol=1 lock_reclaim_batch=0 lock_reclaim_batch_per=3"
# TEST_CASES[16]="lru_resize=0 lock_reclaim_pol=1 lock_reclaim_batch=0 lock_reclaim_batch_per=5"
# TEST_CASES[17]="lru_resize=0 lock_reclaim_pol=1 lock_reclaim_batch=0 lock_reclaim_batch_per=7"
# TEST_CASES[18]="lru_resize=0 lock_reclaim_pol=1 lock_reclaim_batch=0 lock_reclaim_batch_per=10"
# TEST_CASES[19]="lru_resize=0 lock_reclaim_pol=1 lock_reclaim_batch=0 lock_reclaim_batch_per=15"
# TEST_CASES[20]="lru_resize=0 lock_reclaim_pol=0 lock_reclaim_batch=512 lock_reclaim_batch_per=2"
# TEST_CASES[21]="lru_resize=0 lock_reclaim_pol=0 lock_reclaim_batch=0 lock_reclaim_batch_per=2"

# TEST_CASES[22]="lru_resize=0 lru_max_age=1 lock_reclaim_pol=1 lock_reclaim_batch=0 lock_reclaim_batch_per=5"
# TEST_CASES[23]="lru_resize=0 lru_max_age=3 lock_reclaim_pol=1 lock_reclaim_batch=0 lock_reclaim_batch_per=5"
# TEST_CASES[24]="lru_resize=0 lru_max_age=5 lock_reclaim_pol=1 lock_reclaim_batch=0 lock_reclaim_batch_per=5"
# TEST_CASES[25]="lru_resize=0 lru_max_age=10 lock_reclaim_pol=1 lock_reclaim_batch=0 lock_reclaim_batch_per=5"
# TEST_CASES[26]="lru_resize=0 lru_max_age=30 lock_reclaim_pol=1 lock_reclaim_batch=0 lock_reclaim_batch_per=5"

# TEST_CASES[27]="lru_resize=0 lru_max_age=1 lock_reclaim_pol=1 lock_reclaim_batch=0 lock_reclaim_batch_per=2"
# TEST_CASES[28]="lru_resize=0 lru_max_age=3 lock_reclaim_pol=1 lock_reclaim_batch=0 lock_reclaim_batch_per=2"
# TEST_CASES[29]="lru_resize=0 lru_max_age=5 lock_reclaim_pol=1 lock_reclaim_batch=0 lock_reclaim_batch_per=2"
# TEST_CASES[30]="lru_resize=0 lru_max_age=10 lock_reclaim_pol=1 lock_reclaim_batch=0 lock_reclaim_batch_per=2"
# TEST_CASES[31]="lru_resize=0 lru_max_age=30 lock_reclaim_pol=1 lock_reclaim_batch=0 lock_reclaim_batch_per=2"

# TEST_CASES[32]="elc=0 lru_resize=1 lock_reclaim_pol=1 lock_reclaim_batch=512 lock_reclaim_batch_per=1"
# TEST_CASES[33]="elc=0 lru_resize=0 lock_reclaim_pol=1 lock_reclaim_batch=512 lock_reclaim_batch_per=1"
# TEST_CASES[34]="elc=0 lru_resize=0 lock_reclaim_pol=1 lock_reclaim_batch=0 lock_reclaim_batch_per=1"
# TEST_CASES[35]="elc=0 lru_resize=0 lock_reclaim_pol=1 lock_reclaim_batch=0 lock_reclaim_batch_per=3"
# TEST_CASES[36]="elc=0 lru_resize=0 lock_reclaim_pol=1 lock_reclaim_batch=0 lock_reclaim_batch_per=5"
# TEST_CASES[37]="elc=0 lru_resize=0 lock_reclaim_pol=1 lock_reclaim_batch=0 lock_reclaim_batch_per=7"
# TEST_CASES[38]="elc=0 lru_resize=0 lock_reclaim_pol=1 lock_reclaim_batch=0 lock_reclaim_batch_per=10"
# TEST_CASES[39]="elc=0 lru_resize=0 lock_reclaim_pol=1 lock_reclaim_batch=0 lock_reclaim_batch_per=15"
# TEST_CASES[40]="elc=0 lru_resize=0 lock_reclaim_pol=0 lock_reclaim_batch=512 lock_reclaim_batch_per=2"
# TEST_CASES[41]="elc=0 lru_resize=0 lock_reclaim_pol=0 lock_reclaim_batch=0 lock_reclaim_batch_per=2"

# TEST_CASES[0]="lru_resize=1"
# TEST_CASES[1]="lru_resize=0 lock_reclaim_pol=1 lock_reclaim_batch=512"
# TEST_CASES[2]="lru_resize=0 lock_reclaim_pol=1 lock_reclaim_batch=0 lock_reclaim_batch_per=1"
# TEST_CASES[3]="lru_resize=0 lock_reclaim_pol=1 lock_reclaim_batch=0 lock_reclaim_batch_per=3"
# TEST_CASES[4]="lru_resize=0 lock_reclaim_pol=1 lock_reclaim_batch=0 lock_reclaim_batch_per=5"
# TEST_CASES[5]="lru_resize=0 lock_reclaim_pol=1 lock_reclaim_batch=0 lock_reclaim_batch_per=7"
# TEST_CASES[6]="lru_resize=0 lock_reclaim_pol=1 lock_reclaim_batch=0 lock_reclaim_batch_per=10"
# TEST_CASES[7]="lru_resize=0 lock_reclaim_pol=1 lock_reclaim_batch=0 lock_reclaim_batch_per=15"
# TEST_CASES[8]="lru_resize=0 lock_reclaim_pol=0 lock_reclaim_batch=512"
# TEST_CASES[9]="lru_resize=0 lock_reclaim_pol=0 lock_reclaim_batch=0 lock_reclaim_batch_per=2"
# TEST_CASES[10]="lru_resize=1"
# TEST_CASES[11]="lru_resize=1"
# TEST_CASES[12]="lru_resize=1"

# TEST_CASES[13]="lru_resize=0 lock_reclaim_pol=1 lock_reclaim_batch=512"
# TEST_CASES[14]="lru_resize=0 lock_reclaim_pol=1 lock_reclaim_batch=0 lock_reclaim_batch_per=1"
# TEST_CASES[15]="lru_resize=0 lock_reclaim_pol=1 lock_reclaim_batch=0 lock_reclaim_batch_per=3"
# TEST_CASES[16]="lru_resize=0 lock_reclaim_pol=1 lock_reclaim_batch=0 lock_reclaim_batch_per=5"
# TEST_CASES[17]="lru_resize=0 lock_reclaim_pol=1 lock_reclaim_batch=0 lock_reclaim_batch_per=7"
# TEST_CASES[18]="lru_resize=0 lock_reclaim_pol=1 lock_reclaim_batch=0 lock_reclaim_batch_per=10"
# TEST_CASES[19]="lru_resize=0 lock_reclaim_pol=1 lock_reclaim_batch=0 lock_reclaim_batch_per=15"
# TEST_CASES[20]="lru_resize=0 lock_reclaim_pol=0 lock_reclaim_batch=512"
# TEST_CASES[21]="lru_resize=0 lock_reclaim_pol=0 lock_reclaim_batch=0 lock_reclaim_batch_per=2"

# TEST_CASES[22]="lru_resize=0 lru_max_age=1 lock_reclaim_pol=1 lock_reclaim_batch=0 lock_reclaim_batch_per=5"
# TEST_CASES[23]="lru_resize=0 lru_max_age=3 lock_reclaim_pol=1 lock_reclaim_batch=0 lock_reclaim_batch_per=5"
# TEST_CASES[24]="lru_resize=0 lru_max_age=5 lock_reclaim_pol=1 lock_reclaim_batch=0 lock_reclaim_batch_per=5"
# TEST_CASES[25]="lru_resize=0 lru_max_age=10 lock_reclaim_pol=1 lock_reclaim_batch=0 lock_reclaim_batch_per=5"
# TEST_CASES[26]="lru_resize=0 lru_max_age=30 lock_reclaim_pol=1 lock_reclaim_batch=0 lock_reclaim_batch_per=5"

# TEST_CASES[27]="lru_resize=0 lru_max_age=1 lock_reclaim_pol=1 lock_reclaim_batch=0 lock_reclaim_batch_per=2"
# TEST_CASES[28]="lru_resize=0 lru_max_age=3 lock_reclaim_pol=1 lock_reclaim_batch=0 lock_reclaim_batch_per=2"
# TEST_CASES[29]="lru_resize=0 lru_max_age=5 lock_reclaim_pol=1 lock_reclaim_batch=0 lock_reclaim_batch_per=2"
# TEST_CASES[30]="lru_resize=0 lru_max_age=10 lock_reclaim_pol=1 lock_reclaim_batch=0 lock_reclaim_batch_per=2"
# TEST_CASES[31]="lru_resize=0 lru_max_age=30 lock_reclaim_pol=1 lock_reclaim_batch=0 lock_reclaim_batch_per=2"

# TEST_CASES[32]="elc=0 lru_resize=1"
# TEST_CASES[33]="elc=0 lru_resize=0 lock_reclaim_pol=1 lock_reclaim_batch=512"
# TEST_CASES[34]="elc=0 lru_resize=0 lock_reclaim_pol=1 lock_reclaim_batch=0 lock_reclaim_batch_per=1"
# TEST_CASES[35]="elc=0 lru_resize=0 lock_reclaim_pol=1 lock_reclaim_batch=0 lock_reclaim_batch_per=3"
# TEST_CASES[36]="elc=0 lru_resize=0 lock_reclaim_pol=1 lock_reclaim_batch=0 lock_reclaim_batch_per=5"
# TEST_CASES[37]="elc=0 lru_resize=0 lock_reclaim_pol=1 lock_reclaim_batch=0 lock_reclaim_batch_per=7"
# TEST_CASES[38]="elc=0 lru_resize=0 lock_reclaim_pol=1 lock_reclaim_batch=0 lock_reclaim_batch_per=10"
# TEST_CASES[39]="elc=0 lru_resize=0 lock_reclaim_pol=1 lock_reclaim_batch=0 lock_reclaim_batch_per=15"
# TEST_CASES[40]="elc=0 lru_resize=0 lock_reclaim_pol=0 lock_reclaim_batch=512"
# TEST_CASES[41]="elc=0 lru_resize=0 lock_reclaim_pol=0 lock_reclaim_batch=0 lock_reclaim_batch_per=2"

# TEST_CASES[0]="lru_resize=1"
# TEST_CASES[1]="lru_resize=1"
# TEST_CASES[2]="lru_resize=1"
# TEST_CASES[3]="lru_resize=1"
# TEST_CASES[4]="lru_resize=1"
# TEST_CASES[5]="lru_resize=1"
# TEST_CASES[6]="lru_resize=1"
# TEST_CASES[7]="lru_resize=1"
# TEST_CASES[8]="lru_resize=1"
# TEST_CASES[9]="lru_resize=1"
# TEST_CASES[10]="lru_resize=1"
# TEST_CASES[11]="lru_resize=1"
# TEST_CASES[12]="lru_resize=1"

TEST_CASES[13]="lru_resize=0 lock_reclaim_pol=1 lock_reclaim_batch=512 lock_reclaim_threshold_mb=87"
TEST_CASES[14]="lru_resize=0 lock_reclaim_pol=1 lock_reclaim_batch=0 lock_reclaim_batch_per=1 lock_reclaim_threshold_mb=87"
TEST_CASES[15]="lru_resize=0 lock_reclaim_pol=1 lock_reclaim_batch=0 lock_reclaim_batch_per=3 lock_reclaim_threshold_mb=87"
TEST_CASES[16]="lru_resize=0 lock_reclaim_pol=1 lock_reclaim_batch=0 lock_reclaim_batch_per=5 lock_reclaim_threshold_mb=87"
TEST_CASES[17]="lru_resize=0 lock_reclaim_pol=1 lock_reclaim_batch=0 lock_reclaim_batch_per=7 lock_reclaim_threshold_mb=87"
TEST_CASES[18]="lru_resize=0 lock_reclaim_pol=1 lock_reclaim_batch=0 lock_reclaim_batch_per=10 lock_reclaim_threshold_mb=87"
TEST_CASES[19]="lru_resize=0 lock_reclaim_pol=1 lock_reclaim_batch=0 lock_reclaim_batch_per=15 lock_reclaim_threshold_mb=87"

# Other common parameters (can be varied too, if needed)
# COMMON_PARAMS="debug=0 elc=1"
COMMON_PARAMS="debug=0"

# --- Main Logic ---

mkdir -p "$OUTPUT_DIR"
echo "Starting experiments. Results will be stored in $OUTPUT_DIR"
echo "---------------------------------------------------------"

for i in "${!TEST_CASES[@]}"; do
    TEST_CASE="${TEST_CASES[$i]}"
    EXPERIMENT_NAME="EXP_$(printf "%02d" $((i+1)))_${TEST_CASE// /_}"

    echo ">>> Running Experiment $EXPERIMENT_NAME"
    
    # 1. Prepare environment variables to be injected into cli.sh
    # We use a temporary file to hold the new variables.
    TEMP_CONFIG="$OUTPUT_DIR/temp_config.sh"
    
    echo "#!/bin/bash" > "$TEMP_CONFIG"
    echo "# Configuration override for $EXPERIMENT_NAME" >> "$TEMP_CONFIG"
    
    # Inject common parameters
    for param in $COMMON_PARAMS; do
        echo "$param" >> "$TEMP_CONFIG"
    done
    
    # Inject test specific parameters (elc, lru_resize)
    for param in $TEST_CASE; do
        echo "$param" >> "$TEMP_CONFIG"
    done
    
    # 2. Execute the main cli.sh script
    # The source command ensures that the variables from TEMP_CONFIG are loaded BEFORE cli.sh runs.
    # Note: This requires manually editing cli.sh to source this config file first (see below).
    #
    # ALTERNATIVE (Easier method): Run cli.sh with variables set in the environment.
    (
        export $COMMON_PARAMS $TEST_CASE
        
        # Run the experiment. stdout/stderr are saved to a log file.
        # We need to run the CLI_SCRIPT in the same shell to ensure exported variables take effect.
        echo "Running: $CLI_SCRIPT"
        bash "$CLI_SCRIPT" 2>&1 | tee "$OUTPUT_DIR/$EXPERIMENT_NAME.log"
    )

    # --- Check for successful run ---
    if [ $? -ne 0 ]; then
        echo "⚠️ WARNING: Experiment $EXPERIMENT_NAME failed. Skipping artifact collection and plotting."
        echo "---------------------------------------------------------"
        continue
    fi

    # 3. Collect and rename output files
    echo "Collecting artifacts for $EXPERIMENT_NAME..."

    # Define artifact names using the EXPERIMENT_NAME prefix
    ARTIFACT_CLI_TRACE="$OUTPUT_DIR/$EXPERIMENT_NAME.cli_trace.txt"
    ARTIFACT_MDS_TRACE="$OUTPUT_DIR/$EXPERIMENT_NAME.mds_trace.txt"
    
    # Files generated by cli.sh
    mv cli_trace.txt "$ARTIFACT_CLI_TRACE"
    mv res_mdtest.txt "$OUTPUT_DIR/$EXPERIMENT_NAME.res_mdtest.txt"
    if [ -f "mds_trace.txt" ]; then
        mv mds_trace.txt "$ARTIFACT_MDS_TRACE"
    fi
    if [ -f "cli_log" ]; then
        mv cli_log "$OUTPUT_DIR/$EXPERIMENT_NAME.cli_log"
    fi
    if [ -f "mds_log" ]; then
        mv mds_log "$OUTPUT_DIR/$EXPERIMENT_NAME.mds_log"
    fi

    # 4. Generate Plot (NEW STEP)
    echo "Generating plot for $EXPERIMENT_NAME..."
    if [ -f "$DRAW_SCRIPT" ] && [ -f "$ARTIFACT_CLI_TRACE" ] && [ -f "$ARTIFACT_MDS_TRACE" ]; then
        # Call draw.py with plot_name, file1 (cli_trace), file2 (mds_trace)
        python3 "$DRAW_SCRIPT" "$((i+1))" "$ARTIFACT_CLI_TRACE" "$ARTIFACT_MDS_TRACE"
        
        if [ $? -eq 0 ]; then
            # The python script saves the figure as figure_<param>.png
            PLOTTED_FILE="figure_$((i+1)).png"
            FIN_FILE="$EXPERIMENT_NAME.png"
            mv "$PLOTTED_FILE" "$FIN_FILE"
            # Move the generated plot into the experiment results directory
            mv "$FIN_FILE" "$OUTPUT_DIR/"
            echo "Plot generated: $OUTPUT_DIR/$PLOTTED_FILE"
        else
            echo "Plot generation FAILED. Check draw.py."
        fi
    else
        echo "Skipping plot: Cannot find $DRAW_SCRIPT or necessary trace files."
    fi
    
    echo "Experiment $EXPERIMENT_NAME finished."
    echo "---------------------------------------------------------"
done

echo "All experiments complete. Check $OUTPUT_DIR for results."
