
cd ../../

# 引擎调试 真机
./flutter/tools/gn --ios --unoptimized
ninja -C ./out/ios_debug_unopt
# 引擎调试 真机 armv7
./flutter/tools/gn --ios --ios-cpu arm --unoptimized
ninja -C ./out/ios_debug_unopt_arm
# 引擎调试 模拟器
./flutter/tools/gn --ios --simulator --unoptimized
ninja -C ./out/ios_debug_sim_unopt