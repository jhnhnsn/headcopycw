import subprocess
import os

work_dir = r"D:\github\claudemobileapptest"
os.chdir(work_dir)

print("=== Environment Check ===\n")

# Check cmake
result = subprocess.run(["cmake", "--version"], capture_output=True, text=True, shell=True)
print(f"cmake --version: {result.stdout.strip()}")

# Check cl.exe via where
result = subprocess.run(["where", "cl"], capture_output=True, text=True, shell=True)
print(f"where cl: {result.stdout.strip() if result.returncode == 0 else 'NOT FOUND'}")

# Check if we can run cmake with VS generator
print("\n=== Testing CMake with Visual Studio generator ===\n")
test_dir = os.path.join(work_dir, "cmake_test")
os.makedirs(test_dir, exist_ok=True)

# Create a minimal CMakeLists.txt
with open(os.path.join(test_dir, "CMakeLists.txt"), "w") as f:
    f.write("""cmake_minimum_required(VERSION 3.14)
project(test_project CXX)
message(STATUS "C++ Compiler: ${CMAKE_CXX_COMPILER}")
""")

os.chdir(test_dir)
result = subprocess.run(
    ["cmake", "-G", "Visual Studio 17 2022", "."],
    capture_output=True, text=True
)
print("STDOUT:", result.stdout)
print("STDERR:", result.stderr)
print(f"Exit code: {result.returncode}")

# Cleanup
os.chdir(work_dir)
import shutil
shutil.rmtree(test_dir, ignore_errors=True)

# Now check what Flutter is doing
print("\n=== Flutter Windows Build Directory ===\n")
windows_build = os.path.join(work_dir, "build", "windows", "x64")
if os.path.exists(windows_build):
    print(f"Build dir exists: {windows_build}")
    for f in os.listdir(windows_build):
        print(f"  {f}")
else:
    print(f"Build dir does not exist yet: {windows_build}")

# Check the Flutter CMakeLists.txt
print("\n=== Flutter Windows CMakeLists.txt ===\n")
flutter_cmake = os.path.join(work_dir, "windows", "CMakeLists.txt")
if os.path.exists(flutter_cmake):
    with open(flutter_cmake, 'r') as f:
        print(f.read()[:500])
else:
    print("windows/CMakeLists.txt not found - run 'flutter create .' first")
