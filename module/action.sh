# s23-ultra-tweaks: the module's action button in the KernelSU app (output shows as a log screen).
# Applies the saved picks and follows the apply's log until it finishes or 6 minutes pass.
MODDIR=${0%/*}
V=/data/adb/s23tweaks; L=$V/tweaks.log
unset ASH_STANDALONE   # tweaks.sh runs with Android's own sh and tools, as from adb or the module page

t=$(cat $V/choices 2>/dev/null); t=$(echo $t)
if [ -z "$t" ]; then
  echo "Open the module page to choose tweaks first (KernelSU > Modules > S23 Ultra Tweaks > the page icon)."
  exit 0
fi

echo "Applying your saved picks: $t"
case " $t " in *" airdrop "*|*" wifi7 "*) echo "Wi-Fi drops for ~30 s while the Wi-Fi driver is swapped." ;; esac
echo "The screen may go black for ~30 s while Android restarts, and this screen will close."
echo "The apply carries on by itself; the module page shows the result."
echo

out=$(/system/bin/sh "$MODDIR/tweaks.sh" start "$t" 2>&1); rc=$?
case $rc in
  0) ;;
  3) echo "$out"; echo "Following that apply instead:" ;;
  *) echo "$out"; exit 1 ;;
esac

shown=0; end=$(( $(date +%s) + 360 ))
while [ "$(date +%s)" -lt $end ]; do
  sleep 2
  [ -f $L ] || continue
  n=$(grep -c '' $L)
  [ "$n" -lt $shown ] && shown=0          # the log was restarted
  [ "$n" -gt $shown ] || continue
  sed -n "$((shown + 1)),${n}p" $L | sed 's/^[0-9.]* //'
  shown=$n
  if grep -q '^[0-9.]* DONE$' $L; then echo; echo "Done."; exit 0; fi
  if grep -q '^[0-9.]* FAILED:' $L; then echo; echo "The apply stopped at the line above. A reboot undoes everything it changed."; exit 1; fi
done
echo
echo "Still running after 6 minutes. The module page shows the progress (log: $L)."
