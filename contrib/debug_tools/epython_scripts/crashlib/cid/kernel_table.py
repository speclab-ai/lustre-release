
"""
Provide access to kernel_table data.
Copyright 2014 Cray Inc.  All Rights Reserved
"""

from pykdump.API import *

import crashlib.cid

class KernelInfo:
    """Provide access to the crash kernel_table.

    The data is collected by parsing the output of the 'help -k' command.
    """

    def __init__(self):
        """Extract kernel data from crash.

        Initialize the table of kernel information by parsing the output
        of the 'help -k' command.  This only extracts selected data.

        Each item extracted is made available as an instance attribute.
        """

        # crash 'help -k' doesn't use prefixes on numbers, so we must
        # know what number base is in use for each numeric field.
        decFields = ('cpus', 'NR_CPUS', 'kernel_NR_CPUS')

        hexFields = ('flags', 'stext', 'etext', 'stext_init', 'etext_init',
            'init_begin', 'init_end', 'end', 'module_list', 'kernel_module')

        expected_key_count = len(decFields) + len(hexFields)

        for line in exec_crash_command('help -k').splitlines():
            # crash> help -k
            #        NR_CPUS: 4096 (compiled-in to this version of crash)
            #  ...
            #
            # Only use the first value after the field name and
            # only for selected fields.
            parts = line.split()
            if len(parts) < 2: continue
            key = parts[0].rstrip(':')
            if key in decFields:
                self.__dict__[key] = int(parts[1],10)
            elif key in hexFields:
                self.__dict__[key] = int(parts[1],16)

        # If some versions of crash or the kernel don't have all the
        # fields, this check code may need to be removed or modified.
        if len(self.__dict__.keys()) != expected_key_count:
            raise crashlib.cid.ParseError(
                'Expected {:d}, but parsed {:d} entries.'.format(
                    expected_key_count, len(self.__dict__.keys())))

# --------------------------------------------------------------------------

# Create a shared instances.

crashlib.cid.krntbl = KernelInfo()
