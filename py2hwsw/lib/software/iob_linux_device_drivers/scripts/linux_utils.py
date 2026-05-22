# SPDX-FileCopyrightText: 2025 IObundle
#
# SPDX-License-Identifier: MIT

import copy
import re

#################################################################################################
# These functions are duplicate/derived from the ones in csr_gen.py.
# Ideally, we should get these values from csr_gen directly, but Py2HWSW does not provide a mechanism to do this.
#################################################################################################


def csr_type(n_bits):
    type_dict = {8: "uint8_t", 16: "uint16_t", 32: "uint32_t"}
    try:
        n_bits = int(n_bits)
    except (ValueError, TypeError):
        # If its not an integer, or its too big, default to 32
        # NOTE: Ideally, we should try to evaluate verilog parameters contained in n_bits.
        #       The best solution would be to obatin the evaluated value from the iob_csrs module directly.
        #       But currently py2hwsw does not have an easy mechanism to do that.
        return "uint32_t"

    for type_try in type_dict:
        if n_bits <= type_try:
            return type_dict[type_try]


def clog2(val):
    """Used by eval_param_expression"""
    return ceil(log2(val))


def eval_param_expression(param_expression, params_dict):
    """Given a mathematical string with parameters, replace every parameter by
    its numeric value and tries to evaluate the string.
    param_expression: string defining a math expression that may contain parameters
    params_dict: dictionary of parameters, where the key is the parameter name and the value is its value
    """
    if type(param_expression) is int:
        return param_expression
    else:
        original_expression = param_expression
        # Split string to separate parameters/macros from the rest
        split_expression = re.split(r"([^\w_])", param_expression)
        # Replace each parameter, following the reverse order of parameter list.
        # The reversed order allows replacing parameters recursively (parameters may
        # have values with parameters that came before).
        for param_name, param_value in reversed(params_dict.items()):
            # Replace every instance of this parameter by its value
            for idx, word in enumerate(split_expression):
                if word == param_name:
                    # Replace parameter/macro by its value
                    split_expression[idx] = str(param_value)
                    # Remove '`' char if it was a macro
                    if idx > 0 and split_expression[idx - 1] == "`":
                        split_expression[idx - 1] = ""
                    # resplit the string in case the parameter value contains other parameters
                    split_expression = re.split(r"([^\w_])", "".join(split_expression))
        # Join back the string
        param_expression = "".join(split_expression)
        # Evaluate $clog2 expressions
        param_expression = param_expression.replace("$clog2", "clog2")
        # Evaluate IOB_MAX and IOB_MIN expressions
        param_expression = param_expression.replace("iob_max", "max")
        param_expression = param_expression.replace("iob_min", "min")

        # Try to calculate string as it should only contain numeric values
        try:
            return eval(param_expression)
        except:
            sys.exit(
                f"Error: string '{original_expression}' evaluated to '{param_expression}' is not a numeric expression."
            )


def eval_param_expression_from_config(param_expression, confs, param_attribute):
    """Given a mathematical string with parameters, replace every parameter by its
    numeric value and tries to evaluate the string. The parameters are taken from the
    confs dictionary.
    param_expression: string defining a math expression that may contain parameters.
    confs: list of dictionaries, each of which describes a parameter and has attributes:
           'name', 'val' and 'max'.
    param_attribute: name of the attribute in the paramater that contains the value to
           replace in string given. Attribute names are: 'val', 'min, or 'max'.
    """
    # Create parameter dictionary with correct values to be replaced in string
    params_dict = {}
    for conf in confs:
        if conf["type"] in ["P", "D"]:  # Use given param_attribute
            params_dict[conf["name"]] = conf.get(param_attribute, None)
        else:  # M or C - Always use 'val'
            params_dict[conf["name"]] = conf.get("val", None)

    return eval_param_expression(param_expression, params_dict)


#################################################################################################


def evaluate_peripheral_csrs_widths(peripheral):
    evaluated_peripheral = copy.deepcopy(peripheral)
    for csr in evaluated_peripheral["csrs"]:
        csr["n_bits"] = eval_param_expression_from_config(
            csr["n_bits"], peripheral["confs"], "max"
        )

    print(evaluated_peripheral)
    return evaluated_peripheral
