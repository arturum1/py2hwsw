# SPDX-FileCopyrightText: 2025 IObundle
#
# SPDX-License-Identifier: MIT

# Vitis Python script to generate FSBL for Zynq boards

import os
import sys
import shutil
import vitis

name = sys.argv[1]

# Create a Vitis client object, which acts as the interface between this Python script and the Vitis IDE/toolchain.
client = vitis.create_client()

# Remove old workspace if it exists
if os.path.exists("./vitis_ws"):
    shutil.rmtree("./vitis_ws")

# Set the workspace directory where Vitis projects, build files, and outputs will be stored.
client.set_workspace(path="./vitis_ws")

# Create a platform component object representing your hardware platform based on the provided XSA file.
# Specify the target CPU (PS7 Cortex-A53) and the operating system environment (standalone for FSBL).
# The platform is created inside a named domain (logical grouping of embedded projects).
print("Creating platform...")
platform_comp = client.create_platform_component(
    name="platform",
    hw_design="hw_platform.xsa",
    cpu="ps7_cortexa9_0",
    os="standalone",
    domain_name="standalone_domain",
)

# Build the platform component. This prepares the platform and generates necessary BSPs and platform files.
print("Building platform...")
platform_comp.build()

# Create an application component to be built on top of the platform.
# This specifies the application name, the platform to target (path to the exported platform file).
# The domain must match the platform's domain.
# Use the 'empty_application' template to create an empty application (still includes an auto-generated FSBL that configures the platform).
# Run this command to see available templates: 'empyro validate_bsp --help'
print("Creating application...")
app_comp = client.create_app_component(
    name=name,
    platform="./vitis_ws/platform/export/platform/platform.xpfm",
    domain="standalone_ps7_cortexa9_0",
    template="empty_application",
)

# Create a minimal main.c source file inside the application folder
app_src_dir = f"./vitis_ws/{name}/src"
os.makedirs(app_src_dir, exist_ok=True)
main_c_path = os.path.join(app_src_dir, "main.c")

with open(main_c_path, "w") as f:
    f.write(
        """
int main() {
    return 0;
}
"""
    )

# Add the source file to the application component
# Note: The Python Vitis API does not expose a direct method to add sources explicitly.
# Usually, placing the source file in the src folder suffices if the application template supports it.
# If needed, use the 'empty_application' template or switch to a minimal template that picks src files.

# Build the FSBL application, compiling it into an executable ELF that can run on your processor.
print("Building application...")
app_comp.build()

# Elf generated in: <workspace>/<fsbl_project_name>/<build-config>/<fsbl_project_name>.elf
# Example: ./vitis_ws/iob_system/build/iob_system.elf

client.close()
