# Dont use '~' write the full path or use $HOME
APK="./amongus.apk"
MODMENU_APK="$HOME/ApkProjects/ImpostorMenu/app/build/outputs/apk/release/app-release-unsigned.apk"

# Signing configuration
KEYSTORE="$HOME/keystore/ImpostorMenu.keystore"

OUTPUT="$PWD/amongus-impostor-v1.3.apk"
WDIR=`mktemp -d -p "/tmp/"`

if [[ ! "$WDIR" || ! -d "$WDIR" ]]; then
	echo "Could not create temp dir"
	exit 1
fi

function cleanup {
	rm -rf "$WDIR"
	echo "[+] Removed $WDIR"
}

trap cleanup EXIT

echo "APK=$APK"
echo "MODMENU_APK=$MODMENU_APK"
echo "OUTPUT=$OUTPUT"
echo "KEYSTORE=$KEYSTORE"
echo "WDIR=$WDIR"
echo ""

if [ ! -f "$MODMENU_APK" ]; then
	echo ""
    echo "[-] ERROR: MODMENU_APK file does not exist"
	exit 1
fi

if [ ! -f "$APK" ]; then
	echo ""
    echo "[-] ERROR: APK file does not exist"
	exit 1
fi

# fix exceptions with apktool
apktool empty-framework-dir > /dev/null

# Copy xapk to tmp working directory
echo ""
echo "[+] Copying files"
cp $APK $WDIR
cp $MODMENU_APK $WDIR/
XAPK=$(basename "$APK")
MODMENU_APK=$(basename "$MODMENU_APK")

cd $WDIR
echo ""
echo "[+] Decompiling $MODMENU_APK file"
apktool d $(basename "$MODMENU_APK")
MODMENU_APK="${MODMENU_APK%.apk}"

echo ""
echo "[+] Decompiling $(basename $APK) file"
apktool d $APK
APK=$(basename $APK)
APK="${APK%.apk}"

echo ""
echo "[+] Copying libraries"
cp -r $MODMENU_APK/lib/* $APK/lib/

#rm -rf $APK/lib/arm64-v8a/

echo "[+] Copying assets"
cp $MODMENU_APK/assets/* $APK/assets/

echo "[+] Copying smali files"

mkdir -p $APK/smali/com/devilx86/modmenu
cp -r $MODMENU_APK/smali/com/devilx86/modmenu/Menu* $APK/smali/com/devilx86/modmenu

echo "[+] Injecting startup code"
LineNumber=$(($(cat $APK/smali/com/unity3d/player/UnityPlayerActivity.smali | grep -n "requestFocus()" | cut -f1 -d: | sort -u | head -n 1) - 1))
inject_code="\n    invoke-static \{p0\}, Lcom\/devilx86\/modmenu\/MenuMain;->initModMenu(Landroid\/content\/Context;)V"

awk -v n=$LineNumber -v s="$inject_code" 'NR == n {print s} {print}' $APK/smali/com/unity3d/player/UnityPlayerActivity.smali > $APK/smali/com/unity3d/player/UnityPlayerActivity.smali.mod

echo "[+] Diffing code modifications:"
diff $APK/smali/com/unity3d/player/UnityPlayerActivity.smali $APK/smali/com/unity3d/player/UnityPlayerActivity.smali.mod
mv $APK/smali/com/unity3d/player/UnityPlayerActivity.smali.mod $APK/smali/com/unity3d/player/UnityPlayerActivity.smali

echo ""
echo "[+] Updating Manifest"
cp $APK/AndroidManifest.xml $APK/AndroidManifest.xml.original

# Modify manifest
LineNumber=$(($(cat $APK/AndroidManifest.xml | grep -n "<uses-permission " | cut -f1 -d: | sort -u | head -n 1) + 1))
inject_code="    <uses-permission android:name=\"android.permission.SYSTEM_ALERT_WINDOW\"\/>"
awk -v n=$LineNumber -v s="$inject_code" 'NR == n {print s} {print}' $APK/AndroidManifest.xml > $APK/AndroidManifest.xml.mod

# declare service under application
LineNumber=$(($(cat $APK/AndroidManifest.xml.mod | grep -n "<application " | cut -f1 -d: | sort -u | head -n 1) + 1))
inject_code="        <service android:name=\"com.devilx86.modmenu.MenuService\" android:enabled=\"true\" android:exported=\"false\"\/>"
awk -v n=$LineNumber -v s="$inject_code" 'NR == n {print s} {print}' $APK/AndroidManifest.xml.mod > $APK/AndroidManifest.xml
rm $APK/AndroidManifest.xml.mod

echo "[+] Diffing Manifest modifications:"
diff $APK/AndroidManifest.xml.original $APK/AndroidManifest.xml
rm $APK/AndroidManifest.xml.original

echo ""
echo "[+] Baksmaling apk to $OUTPUT"
apktool b "$APK" -o unaligned.apk

echo "[+] Zip aligning APK"
zipalign -v -p 4 unaligned.apk aligned.apk | head -n 5

mv aligned.apk $OUTPUT

echo ""
echo "[+] Unsigned APK Created: $OUTPUT"

if [ -e $KEYSTORE ]
then
	echo "[+] Signing $OUTPUT"
	zipalign -v -c 4 $OUTPUT | head -n 5
	apksigner sign --ks ~/keystore/ImpostorMenu.keystore $OUTPUT
	zipalign -v -c 4 $OUTPUT | head -n 5
fi
