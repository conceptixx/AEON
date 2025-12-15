# Source the module
source /opt/aeon/lib/progress.sh

# Initialize
init_progress

# Simulate phases
for i in {1..10}; do
    start_phase $i
    sleep 0.5
    for p in {0..100..10}; do
        update_phase_progress $p
        sleep 0.1
    done
    complete_phase "completed"
done

show_completion_summary