# SPDX-FileCopyrightText: 2025 IObundle
#
# SPDX-License-Identifier: MIT

import copy

from iob_base import iob_base, process_elements_from_list, fail_with_msg
from iob_conf import create_conf_group
from iob_port import create_port_from_dict, add_interface_port, add_signals_port
from iob_wire import create_wire, get_wire_signal
from iob_snippet import create_snippet
from iob_globals import iob_globals, create_globals
from iob_comb import iob_comb, create_comb
from iob_fsm import iob_fsm, create_fsm
from iob_block import create_block


class iob_module(iob_base):
    """Class to describe a (Verilog) module"""

    global_top_module = None  # Datatype is 'iob_module'

    def __init__(self, *args, **kwargs):
        # Original name of the module.
        # (The module name commonly used in the files of the setup dir.)
        self.set_default_attribute(
            "original_name",
            "",
            str,
            descr="Original name of the module. Should match name of module's *.py/*.json file. (The module name commonly used in the files of the setup dir.)",
        )
        # Name of the generated module
        self.set_default_attribute(
            "name", "", str, descr="Name of the generated module."
        )
        self.set_default_attribute(
            "description",
            "Default description",
            str,
            descr="Description of the module",
        )
        self.set_default_attribute(
            "reset_polarity",
            None,
            str,
            self.set_rst_polarity,
            "Global reset polarity of the module. Can be 'positive' or 'negative'. (Will override all subblocks' reset polarities).",
        )
        # List of module macros and Verilog (false-)parameters
        self.set_default_attribute(
            "confs",
            [],
            list,
            get_list_attr_handler(self.create_conf_group),
            "List of module macros and Verilog (false-)parameters.",
        )
        self.set_default_attribute(
            "ports",
            [],
            list,
            get_list_attr_handler(self.create_port_from_dict),
            "List of module ports.",
        )
        self.set_default_attribute(
            "wires",
            [],
            list,
            get_list_attr_handler(self.create_wire),
            "List of module wires.",
        )
        # List of core Verilog snippets
        self.set_default_attribute(
            "snippets",
            [],
            list,
            get_list_attr_handler(self.create_snippet),
            "List of core Verilog snippets.",
        )
        # List of core Verilog combinatory circuits
        self.set_default_attribute(
            "comb",
            None,
            iob_comb,
            lambda y: self.create_comb(**y),
            "Verilog combinatory circuit.",
        )
        # List of core Verilog finite state machines
        self.set_default_attribute(
            "fsm",
            None,
            iob_fsm,
            lambda y: self.create_fsm(**y),
            "Verilog finite state machine.",
        )
        # List of instances of other cores inside this core
        self.set_default_attribute(
            "subblocks",
            [],
            list,
            get_list_attr_handler(self.create_subblock),
            "List of instances of other cores inside this core.",
        )
        # List of wrappers for this core
        self.set_default_attribute(
            "superblocks",
            [],
            list,
            get_list_attr_handler(self.create_superblock),
            "List of wrappers for this core. Will only be setup if this core is a top module, or a wrapper of the top module.",
        )
        # List of software modules required by this core
        self.set_default_attribute(
            "sw_modules",
            [],
            list,
            get_list_attr_handler(self.create_sw_instance),
            "List of software modules required by this core.",
        )

    def set_rst_polarity(self, polarity):
        if self.is_top_module:
            create_globals(self, "reset_polarity", polarity)
        else:
            if polarity != getattr(iob_globals(), "reset_polarity", "positive"):
                fail_with_msg(
                    f"Reset polarity '{polarity}' is not the same as global reset polarity '{getattr(iob_globals(), 'reset_polarity', 'positive')}'."
                )

    def create_conf_group(self, *args, **kwargs):
        create_conf_group(self, *args, **kwargs)

    def create_port_from_dict(self, *args, **kwargs):
        create_port_from_dict(self, *args, **kwargs)

    def add_interface_port(self, *args, **kwargs):
        add_interface_port(self, *args, **kwargs)

    def add_signals_port(self, *args, **kwargs):
        add_signals_port(self, *args, **kwargs)

    def create_wire(self, *args, **kwargs):
        create_wire(self, *args, **kwargs)

    def get_wire_signal(self, *args, **kwargs):
        return get_wire_signal(self, *args, **kwargs)

    def create_snippet(self, *args, **kwargs):
        create_snippet(self, *args, **kwargs)

    def create_comb(self, *args, **kwargs):
        create_comb(self, *args, **kwargs)

    def create_fsm(self, *args, **kwargs):
        create_fsm(self, *args, **kwargs)

    def create_superblock(self, *args, **kwargs):
        kwargs.pop("instantiate", None)
        create_block(
            self,
            *args,
            instantiate=False,
            is_superblock=True,
            blocks_attribute_name="superblocks",
            **kwargs,
        )

    def create_subblock(self, *args, **kwargs):
        if self.is_superblock:
            # Remove issuer subblock to ensure that it is not setup again
            if self.handle_issuer_subblock(*args, **kwargs):
                return
        create_block(self, *args, **kwargs)

    def create_sw_instance(self, *args, **kwargs):
        kwargs.pop("instantiate", None)
        self.create_subblock(*args, instantiate=False, **kwargs)

    def update_global_top_module(self):
        """Update global top module if it has not been set before.
        The first module to call this method is the global top module.
        """
        if not __class__.global_top_module:
            __class__.global_top_module = self

    def handle_issuer_subblock(self, *args, **kwargs):
        """If given kwargs describes the issuer subblock, return True. Otherwise return False.
        Also append issuer object found to the core's 'subblocks' list.
        """
        issuer = self.issuer
        if kwargs.get("core_name") == issuer.original_name:
            self.update_issuer_obj(issuer, kwargs)
            return True
        else:
            return False

    def update_issuer_obj(self, issuer_obj, instance_dict):
        """Update given issuer object with values for verilog parameters and external port connections.
        Also, add issuer object to the 'subblocks' list of this superblock.
        :param issuer_obj: issuer object
        :param instance_dict: Dictionary describing verilog instance. Includes port connections and verilog parameter values.
        """
        new_issuer_instance = copy.deepcopy(issuer_obj)
        new_issuer_instance.instantiate = True
        # Set instance name
        if "instance_name" in instance_dict:
            new_issuer_instance.instance_name = instance_dict["instance_name"]
        # Set instance description
        if "instance_description" in instance_dict:
            new_issuer_instance.instance_description = instance_dict[
                "instance_description"
            ]
        # Set values to pass via verilog parameters
        new_issuer_instance.parameters = instance_dict.get("parameters", {})
        # Connect ports of issuer to external wires (wires of this superblock)
        new_issuer_instance.connect_instance_ports(instance_dict.get("connect", {}), self)
        # Create a issuer subblock, and add it to the 'subblocks' list of current superblock
        self.subblocks.append(new_issuer_instance)


def get_list_attr_handler(func):
    """Returns a handler function to set attributes from a list using the function given
    The returned function has the format:
        returned_func(x), where x is a list of elements, likely in the 'py2hw' syntax.
    This 'returned_func' will run the given 'func' on each element of the list 'x'
    """
    return lambda x: process_elements_from_list(
        x,
        # 'y' is a dictionary describing an object in py2hw syntax
        # '**y' is used to unpack the dictionary and pass it as arguments to 'func'
        lambda y: (func(**y) if isinstance(y, dict) else func(y)),
    )
