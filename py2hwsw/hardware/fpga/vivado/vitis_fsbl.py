# SPDX-FileCopyrightText: 2025 IObundle
#
# SPDX-License-Identifier: MIT

# Vitis Python script to generate FSBL for Zynq boards

import sys
import vitis

name = sys.argv[1]

# Create a Vitis client object, which acts as the interface between this Python script and the Vitis IDE/toolchain.
client = vitis.create_client()

# Set the workspace directory where Vitis projects, build files, and outputs will be stored.
client.set_workspace(path="./vitis_ws")

# Create a platform component object representing your hardware platform based on the provided XSA file.
# Specify the target CPU (PS7 Cortex-A53) and the operating system environment (standalone for FSBL).
# The platform is created inside a named domain (logical grouping of embedded projects).
platform_comp = client.create_platform_component(
    name='platform',
    hw_design='hw_platform.xsa',
    cpu='psu_cortexa53_0',
    os='standalone',
    domain_name='standalone_domain'
)

# Build the platform component. This prepares the platform and generates necessary BSPs and platform files.
platform_comp.build()

# Create an application component to be built on top of the platform.
# This specifies the application name, the platform to target (path to the exported platform file).
# The domain must match the platform's domain.
# Use the 'fsbl' template to create the First Stage Boot Loader application.
app_comp = client.create_app_component(
    name=name,
    platform='./vitis_ws/export/platform/platform.xpfm',
    domain='standalone_domain',
    template='fsbl'
)

# Build the FSBL application, compiling it into an executable ELF that can run on your processor.
app_comp.build()

# Elf generated in: <workspace>/<fsbl_project_name>/<build-config>/fsbl.elf
# Example: ./vitis_ws/fsbl_app/Debug/fsbl.elf

client.close()
