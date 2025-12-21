#!/bin/bash

# Menu configuration
options=("Option 1" "Option 2" "Option 3" "Option 4" "Continue")
selected=()
current_line=0
continue_selected=false

# Initialize all options as unchecked (except Continue which can't be checked)
for ((i=0; i<${#options[@]}-1; i++)); do
    selected[$i]=0
done

# Function to display the menu
display_menu() {
    clear
    echo "Use UP/DOWN arrows to navigate, SPACE to toggle, ENTER on Continue to proceed"
    echo "----------------------------------------------------------------"
    
    for ((i=0; i<${#options[@]}; i++)); do
        if [ $i -eq $current_line ]; then
            # Highlight current line
            printf "\033[7m"
        fi
        
        if [ $i -lt $((${#options[@]}-1)) ]; then
            # Regular options with checkboxes
            if [ ${selected[$i]} -eq 1 ]; then
                printf " [✓] %s" "${options[$i]}"
            else
                printf " [ ] %s" "${options[$i]}"
            fi
        else
            # Continue option (no checkbox)
            printf " %s" "${options[$i]}"
        fi
        
        printf "\033[0m\n"
    done
}

# Function to handle continue action
continue_action() {
    clear
    echo "Selected options:"
    echo "-----------------"
    
    for ((i=0; i<${#options[@]}-1; i++)); do
        if [ ${selected[$i]} -eq 1 ]; then
            echo "✓ ${options[$i]}"
        fi
    done
    
    if [ $(echo "${selected[@]}" | tr -d '[:space:]') = "" ]; then
        echo "No options selected"
    fi
    
    echo -e "\nPress any key to exit..."
    read -n 1
    clear
    exit 0
}

# Save terminal settings
original_stty=$(stty -g)

# Set terminal to raw mode for single character reading
stty raw -echo

# Hide cursor
printf "\033[?25l"

# Trap to restore terminal on exit
trap 'printf "\033[?25h"; stty "$original_stty"; clear; exit' EXIT INT

# Initial display
display_menu

# Main input loop
while true; do
    # Read single character (including escape sequences)
    read -n 1 key
    
    if [[ $key == $'\x1b' ]]; then  # Escape sequence (arrows)
        read -n 2 -t 0.001 seq 2>/dev/null
        
        case "$seq" in
            "[A")  # Up arrow
                if [ $current_line -gt 0 ]; then
                    ((current_line--))
                fi
                ;;
            "[B")  # Down arrow
                if [ $current_line -lt $((${#options[@]}-1)) ]; then
                    ((current_line++))
                fi
                ;;
        esac
    elif [[ $key == " " ]]; then  # Space key
        if [ $current_line -lt $((${#options[@]}-1)) ]; then
            # Toggle regular option
            if [ ${selected[$current_line]} -eq 0 ]; then
                selected[$current_line]=1
            else
                selected[$current_line]=0
            fi
        else
            # Space pressed on Continue - treat as selection
            continue_selected=true
        fi
    elif [[ $key == $'\x0d' || $key == "" ]]; then  # Enter key or empty (some terminals)
        if [ $current_line -eq $((${#options[@]}-1)) ] || [ "$continue_selected" = true ]; then
            # Enter pressed on Continue
            break
        fi
    fi
    
    # Redisplay menu
    display_menu
    
    # Reset continue flag
    continue_selected=false
done

# Call continue function
continue_action