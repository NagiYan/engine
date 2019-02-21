

prior_pwd=$PWD
script_path=$(cd "$(dirname "$0")"; pwd)
cd $script_path

# 读取路径配置
config_file="./asc_config"
ASCFlutterCore=""
teldrassil=""

if [[ -e ${config_file} ]]; then
	IFS='='
	while read k v
  		do
      		if [ "$k" = 'ASCFlutterCore' ]; then
      			ASCFlutterCore="${v}"
      		fi

      		if [ "$k" = 'teldrassil' ]; then
      			teldrassil="${v}"
      		fi
	done < ${config_file}

else
	echo "[Flutter] 请在当前目录下创建的 asc_config 文件中指定 teldrassil 和 ASCFlutterCore 的路径，以便产物构建完成后能直接拷贝到对应路径"
	touch asc_config
	echo "ASCFlutterCore=path/ASCFlutterCore" >> ${config_file}
	echo "teldrassil=path/asc_engine" >> ${config_file}
	open ${config_file}
	exit 0
fi

cd ../../

gclient sync

# debug
./flutter/tools/gn --ios
ninja -C ./out/ios_debug

./flutter/tools/gn --ios --ios-cpu arm
ninja -C ./out/ios_debug_arm

# release 
./flutter/tools/gn --ios --simulator
ninja -C ./out/ios_debug_sim

./flutter/tools/gn --ios --runtime-mode=release
ninja -C ./out/ios_release

./flutter/tools/gn --ios --ios-cpu arm --runtime-mode=release
ninja -C ./out/ios_release_arm

# 用于发布release armv7 arm64 + debug版本的x86_64用于模拟器下开发
mv ./out/ios_release/Flutter.framework/Flutter ./out/ios_release/Flutter.framework/Flutter_arm64
lipo -create ./out/ios_release/Flutter.framework/Flutter_arm64 ./out/ios_release_arm/Flutter.framework/Flutter ./out/ios_debug_sim/Flutter.framework/Flutter -output ./out/ios_release/Flutter.framework/Flutter
mv ./out/ios_release/Flutter.framework/Flutter_arm64 ./out/ios_release/

# 用于Flutter业务 x86_64 armv7 arm64
mv ./out/ios_debug/Flutter.framework/Flutter ./out/ios_debug/Flutter.framework/Flutter_arm64
lipo -create ./out/ios_debug/Flutter.framework/Flutter_arm64 ./out/ios_debug_arm/Flutter.framework/Flutter ./out/ios_debug_sim/Flutter.framework/Flutter -output ./out/ios_debug/Flutter.framework/Flutter
mv ./out/ios_debug/Flutter.framework/Flutter_arm64 ./out/ios_debug/

echo "for release ./out/ios_release/Flutter.framework"
echo "for develop ./out/ios_debug/Flutter.framework"


# 最终用于开发的产物

rm -f -r ./out/asc_engine/debug
rm -f -r ./out/asc_engine/release

mkdir ./out/asc_engine
mkdir ./out/asc_engine/debug
mkdir ./out/asc_engine/release

cp ./out/ios_release/clang_x64/gen_snapshot ./out/asc_engine/release/gen_snapshot
cp -f -r ./out/ios_release/Flutter.framework/ ./out/asc_engine/release/Flutter.framework

# 需要合并两种架构，对应arm64和armv7
lipo -create ./out/ios_debug/clang_x64/gen_snapshot ./out/ios_release_arm/clang_x86/gen_snapshot -output ./out/asc_engine/debug/gen_snapshot
cp -f -r ./out/ios_debug/Flutter.framework/ ./out/asc_engine/debug/Flutter.framework

echo "请先确认build无问题，如果有问题请ctrl+c结束打包，没问题按任意键继续"
read -n 1

# 更新产物
# 1 ASCFlutterCore
cp -f -r ./out/asc_engine/release/Flutter.framework/ "${ASCFlutterCore}/Flutter.framework"
cd ${ASCFlutterCore}

git status
echo "请再次确认，接下来会提交产物到git仓库"
read -n 1

git add .

git commit -m "1 更新引擎产物"
git push
echo "ASCFlutterCore updated"

cd $script_path

# 2 Flutter业务主工程teldrassil
cp -f -r ./out/asc_engine/debug/ "${teldrassil}/debug"
cp -f -r ./out/asc_engine/release/ "${teldrassil}/release"
cd ${teldrassil}
git status
echo "please update teldrassil project and commit"

cd $script_path

# 构建发版
open 'http://mtl3.alibaba-inc.com/project/project_build_config.htm?projectId=54960&buildConfigId=520171'

cd ${prior_pwd}