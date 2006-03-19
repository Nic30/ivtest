

# include  <vpi_user.h>
# include  <stdlib.h>

static int memmonitor_compiletf(char*name)
{
      vpiHandle sys = vpi_handle(vpiSysTfCall,0);
      vpiHandle argv = vpi_iterate(vpiArgument, sys);
      vpiHandle arg;

      if (argv == 0) {
	    vpi_printf("ERROR: %s expects at least 1 argument.", name);
	    vpi_sim_control(vpiFinish, 1);
	    return 0;
      }

      while ( (arg = vpi_scan(argv)) ) {
	    if (vpi_get(vpiType, arg) != vpiMemory) {
		  vpi_printf("ERROR: %s expects only memory arguments", name);
		  vpi_sim_control(vpiFinish, 1);
		  return 0;
	    }
      }

      return 0;
}

static PLI_INT32 callback(struct t_cb_data*cb)
{
      vpi_printf("ValueChange: index=%d, value=%s\n",
		 cb->index, cb->value->value.str);
      return 0;
}

static int memmonitor_calltf(char*name)
{
      vpiHandle sys  = vpi_handle(vpiSysTfCall,0);
      vpiHandle argv = vpi_iterate(vpiArgument, sys);
      vpiHandle arg;

      while ( (arg = vpi_scan(argv)) ) {
	    s_cb_data cb_data;

	    cb_data.reason = cbValueChange;
	    cb_data.cb_rtn = callback;
	    cb_data.obj = arg;
	    cb_data.time = 0;
	    cb_data.value = malloc(sizeof(struct t_vpi_value));
	    cb_data.index = 0;
	    cb_data.user_data = 0;

	    cb_data.value->format = vpiBinStrVal;
	    cb_data.value->value.str = 0;

	    vpi_register_cb(&cb_data);
      }

      return 0;
}

static void memmonitor_register(void)
{
      s_vpi_systf_data tf_data;

      tf_data.type      = vpiSysTask;
      tf_data.tfname    = "$memmonitor";
      tf_data.calltf    = memmonitor_calltf;
      tf_data.compiletf = memmonitor_compiletf;
      tf_data.sizetf    = 0;
      tf_data.user_data = "$memmonitor";
      vpi_register_systf(&tf_data);
}

void (*vlog_startup_routines[])() = {
      memmonitor_register,
      0
};