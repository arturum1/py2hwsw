#
#    reg_gen.py: build register files
#

import os

import csr_gen
from iob_csr import iob_csr, iob_csr_group


def find_obj_in_list(obj_list, obj_name, process_func=lambda o: o):
    """Returns an object with a given name from a list of objects
    param obj_list: list of objects (or dictionaries) to search
    param obj_name: name of the object to find
    param process_func: optional function to apply to each object before comparing
    """
    if not obj_list:
        return None
    processed_objs = list(process_func(o) for o in obj_list)
    # Support dictionaries as well
    if isinstance(obj_list[0], dict):
        for obj, obj_processed in zip(obj_list, processed_objs):
            if obj_processed and obj_processed["name"] == obj_name:
                return obj
    else:
        for obj, obj_processed in zip(obj_list, processed_objs):
            if obj_processed and obj_processed.name == obj_name:
                return obj
    return None


def version_str_to_digits(version_str):
    """Given a version string (like "V0.12"), return a 4 digit string representing
    the version (like "0012")"""
    version_str = version_str.replace("V", "")
    major_ver, minor_ver = version_str.split(".")
    return f"{int(major_ver):02d}{int(minor_ver):02d}"


def auto_setup_iob_ctls(core):
    """Auto-add iob_ctls module to blocks list"""
    core["blocks"].append(
        {
            "core_name": "iob_ctls",
            "instance_name": "iob_ctls_inst",
            "instantiate": False,
        },
    )


def build_regs_table(core):
    """Build registers table.
    :returns csr_gen csr_gen_obj: Instance of csr_gen class
    :returns list reg_table: Register table generated by `get_reg_table` method of `csr_gen_obj`
    """
    # Make sure 'general' registers table exists
    general_regs_table = find_obj_in_list(core["csrs"], "general")
    if not general_regs_table:
        general_regs_table = iob_csr_group(
            name="general",
            descr="General Registers.",
            regs=[],
        )
        core["csrs"].append(general_regs_table)

    # Add 'version' register if it does not have one
    if not find_obj_in_list(general_regs_table.regs, "version"):
        general_regs_table.regs.append(
            iob_csr(
                name="version",
                type="R",
                n_bits=16,
                rst_val=version_str_to_digits(core["version"]),
                addr=-1,
                log2n_items=0,
                autoreg=True,
                descr="Product version. This 16-bit register uses nibbles to represent decimal numbers using their binary values. The two most significant nibbles represent the integral part of the version, and the two least significant nibbles represent the decimal part. For example V12.34 is represented by 0x1234.",
            )
        )

    # Create an instance of the csr_gen class inside the csr_gen module
    # This instance is only used locally, not affecting status of csr_gen imported in other functions/modules
    csr_gen_obj = csr_gen.csr_gen()
    csr_gen_obj.config = core["confs"]
    # Get register table
    reg_table = csr_gen_obj.get_reg_table(
        core["csrs"], core["rw_overlap"], core["autoaddr"]
    )

    return csr_gen_obj, reg_table


def generate_reg_hw(core, csr_gen_obj, reg_table):
    """Generate reg hardware files"""
    name = core["name"][: -len("_csrs")]
    csr_gen_obj.write_hwheader(reg_table, core["build_dir"] + "/hardware/src", name)
    csr_gen_obj.write_lparam_header(
        reg_table, core["build_dir"] + "/hardware/simulation/src", name
    )
    csr_gen_obj.write_hwcode(
        reg_table,
        core["build_dir"] + "/hardware/src",
        name,
        core["csr_if"],
        core["confs"],
    )
    csr_gen_obj.write_tbcode(
        reg_table,
        core["build_dir"] + "/hardware/simulation/src",
        name,
    )


def generate_reg_sw(core, csr_gen_obj, reg_table):
    """Generate reg software files"""
    os.makedirs(core["build_dir"] + "/software/src", exist_ok=True)
    name = core["name"][: -len("_csrs")]
    csr_gen_obj.write_swheader(reg_table, core["build_dir"] + "/software/src", name)
    csr_gen_obj.write_swcode(reg_table, core["build_dir"] + "/software/src", name)


def generate_csr(core):
    """Generate hw, sw and doc files"""
    csr_gen_obj, reg_table = build_regs_table(core)
    generate_reg_hw(core, csr_gen_obj, reg_table)
    generate_reg_sw(core, csr_gen_obj, reg_table)
    auto_setup_iob_ctls(core)
    return csr_gen_obj, reg_table