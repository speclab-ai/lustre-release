from lnet_cleanup import clean_lnet
from grumple_cleanup import clean_grumple
import logging

def lutf_clean_setup():
	logging.critical("calling lutf_clean_setup()")
	clean_grumple()
	clean_lnet()
