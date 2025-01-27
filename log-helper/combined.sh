#!/bin/bash

output_file="$HOME/combined_log.txt"
filtered_output_file="$HOME/filtered_log.txt"
summary_file="summary_temp.txt"
focused_summary_file="focused_summary_temp.txt"

# ANSI escape codes for text formatting
BOLD='\033[1m'
RESET='\033[0m'

# Function to display progress bar
show_progress() {
    local width=50
    local percentage=$1
    local filled=$(printf "%.0f" $(echo "$percentage * $width / 100" | bc -l))
    local empty=$((width - filled))
    printf "\rProgress: [%-${width}s] %d%%" $(printf "#%.0s" $(seq 1 $filled)) $percentage
}

# Function to add to summary, ignoring gnome-shell errors
add_to_summary() {
    if ! [[ $1 =~ gnome-shell ]]; then
        echo "$1" >> "$summary_file"
        if [[ $1 =~ i915|amdgpu|wayland|wifi|network|failed ]]; then
            echo "$1" >> "$focused_summary_file"
        fi
    fi
}

# Function to get system information
get_system_info() {
    echo "===== System Information =====" > "$output_file"
    echo "" >> "$output_file"
    echo "Kernel version: $(uname -r)" >> "$output_file"
    echo "Desktop Environment: $XDG_CURRENT_DESKTOP" >> "$output_file"
    echo "Distribution: $(lsb_release -d | cut -f2)" >> "$output_file"
    echo "BIOS Version: $(sudo dmidecode -s bios-version)" >> "$output_file"
    echo "" >> "$output_file"
}

# Function to process logs
process_logs() {
    local start_time=$1
    local end_time=$2
    
    # Convert start and end times to seconds since epoch for comparison
    local start_seconds=$(date -d "$start_time" +%s)
    local end_seconds=$(date -d "$end_time" +%s)

    # Create a header for dmesg section with spacing
    echo "===== dmesg output starts =====" >> "$output_file"
    echo "" >> "$output_file"

    # Collect and filter dmesg output with progress bar
    local total_lines=$(sudo dmesg | wc -l)
    local current_line=0

    sudo dmesg -T | while IFS= read -r line; do
        ((current_line++))
        local percentage=$((current_line * 100 / total_lines))
        show_progress $percentage

        if [[ $line =~ \[(.*?)\] ]]; then
            local timestamp="${BASH_REMATCH[1]}"
            if date -d "$timestamp" &>/dev/null; then
                local line_seconds=$(date -d "$timestamp" +%s)
                if (( line_seconds >= start_seconds && line_seconds <= end_seconds )); then
                    echo "$line" >> "$output_file"
                    if [[ $line =~ error|warning|fail|critical|failed ]]; then
                        add_to_summary "$line"
                    fi
                fi
            fi
        fi
    done

    echo -e "\nDmesg processing complete."

    echo "" >> "$output_file"

    # Create a header for journalctl section with spacing
    echo "" >> "$output_file"
    echo "===== journalctl output starts =====" >> "$output_file"
    echo "" >> "$output_file"

    # Append journalctl output to the file with progress bar
    total_lines=$(sudo journalctl --since="$start_time" --until="$end_time" | wc -l)
    current_line=0

    sudo journalctl --since="$start_time" --until="$end_time" | while IFS= read -r line; do
        ((current_line++))
        percentage=$((current_line * 100 / total_lines))
        show_progress $percentage
        echo "$line" >> "$output_file"
        if [[ $line =~ error|warning|fail|critical|failed ]]; then
            add_to_summary "$line"
        fi
    done

    echo -e "\nJournalctl processing complete."
}

# Function to add summaries to the file
add_summaries() {
    local file=$1
    
    # Add focused summary section to the end of the output file
    echo "" >> "$file"
    echo "===== Focused Summary of Potential Issues =====" >> "$file"
    echo "Issues related to i915, amdgpu, wayland, wifi, network, and failed items:" >> "$file"
    echo "" >> "$file"

    if [ -s "$focused_summary_file" ]; then
        sort "$focused_summary_file" | uniq -c | sort -rn >> "$file"
    else
        echo "No critical issues found related to graphics, display, networking, or failed items." >> "$file"
    fi

    echo "" >> "$file"

    # Add general summary section to the end of the output file
    echo "===== General Summary of Potential Issues (excluding gnome-shell errors) =====" >> "$file"
    echo "" >> "$file"

    if [ -s "$summary_file" ]; then
        sort "$summary_file" | uniq -c | sort -rn >> "$file"
    else
        echo "No other critical issues found in the logs (excluding gnome-shell errors)." >> "$file"
    fi

    echo "" >> "$file"
}

# Main script starts here
echo "Choose an option:"
echo "1. Last x minutes"
echo "2. Last 24 hours"
echo "3. Specific time range"
echo "4. Filter previously created log file"
read choice

case $choice in
  1)
    echo "Enter the number of minutes:"
    read minutes
    start_time=$(date -d "$minutes minutes ago" '+%Y-%m-%d %H:%M')
    end_time=$(date '+%Y-%m-%d %H:%M')
    get_system_info
    process_logs "$start_time" "$end_time"
    add_summaries "$output_file"
    ;;
  2)
    start_time=$(date -d "24 hours ago" '+%Y-%m-%d %H:%M')
    end_time=$(date '+%Y-%m-%d %H:%M')
    get_system_info
    process_logs "$start_time" "$end_time"
    add_summaries "$output_file"
    ;;
  3)
    echo "Enter the start time (YYYY-MM-DD HH:MM):"
    read start_time
    echo "Enter the end time (YYYY-MM-DD HH:MM):"
    read end_time
    get_system_info
    process_logs "$start_time" "$end_time"
    add_summaries "$output_file"
    ;;
  4)
    echo "Looking for file called combined_log.txt in home directory..."
    if [ ! -f "$output_file" ]; then
        echo "File not found: $output_file"
        exit 1
    fi
    echo "File found. Proceeding with filtering options."
    ;;
  *)
    echo "Invalid choice"
    exit 1
    ;;
esac

if [ "$choice" == "4" ]; then
    echo "Choose filtering option:"
    echo "1. Grep for a key phrase"
    echo "2. Grep for a keyword"
    read grep_choice

    case $grep_choice in
      1)
        echo "Enter the key phrase to grep for:"
        read key_phrase
        grep -i -B 3 -A 5 "$key_phrase" "$output_file" > "$filtered_output_file"
        ;;
      2)
        echo "Enter the keyword to grep for:"
        read keyword
        grep -i -w -B 3 -A 5 "$keyword" "$output_file" > "$filtered_output_file"
        ;;
      *)
        echo "Invalid choice. No filtering applied."
        exit 1
        ;;
    esac

    echo -e "\n${BOLD}Filtered log saved in $filtered_output_file${RESET}"
    line_count=$(wc -l < "$filtered_output_file")
    echo -e "${BOLD}Total lines in filtered output: $line_count${RESET}"
else
    echo -e "\n${BOLD}Log collection complete. Results saved in $output_file${RESET}"
    line_count=$(wc -l < "$output_file")
    echo -e "${BOLD}Total lines in output: $line_count${RESET}"
fi

# Remove temporary files
[ -f "$summary_file" ] && rm "$summary_file"
[ -f "$focused_summary_file" ] && rm "$focused_summary_file"
