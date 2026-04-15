#ifndef AWG_SCHED_REGS_H
#define AWG_SCHED_REGS_H

#define AWG_SCHED_REG_CTRL              0x00u
#define AWG_SCHED_REG_STATUS            0x04u
#define AWG_SCHED_REG_EVENT_COUNT       0x08u
#define AWG_SCHED_REG_CUR_EVENT         0x0Cu
#define AWG_SCHED_REG_ERR_REG           0x10u
#define AWG_SCHED_REG_IP_ID             0x14u
#define AWG_SCHED_REG_IP_VERSION        0x18u
#define AWG_SCHED_REG_IP_CAPS           0x1Cu
#define AWG_SCHED_REG_TIME_NOW_LO       0x20u
#define AWG_SCHED_REG_TIME_NOW_HI       0x24u
#define AWG_SCHED_REG_LAST_EXEC_LO      0x28u
#define AWG_SCHED_REG_LAST_EXEC_HI      0x2Cu
#define AWG_SCHED_REG_COMMIT_COUNT      0x30u
#define AWG_SCHED_REG_REINIT_COUNT      0x34u
#define AWG_SCHED_REG_REINIT_REJECT     0x38u
#define AWG_SCHED_REG_IRQ_STATUS        0x3Cu
#define AWG_SCHED_REG_EVT_WADDR         0x40u
#define AWG_SCHED_REG_EVT_WDATA0        0x44u
#define AWG_SCHED_REG_EVT_WDATA1        0x48u
#define AWG_SCHED_REG_EVT_WDATA2        0x4Cu
#define AWG_SCHED_REG_EVT_WDATA3        0x50u
#define AWG_SCHED_REG_EVT_WDATA4        0x54u
#define AWG_SCHED_REG_EVT_WDATA5        0x58u
#define AWG_SCHED_REG_EVT_WDATA6        0x5Cu
#define AWG_SCHED_REG_EVT_WCTRL         0x60u
#define AWG_SCHED_REG_IRQ_ENABLE        0x64u
#define AWG_SCHED_REG_IP_SCRATCH        0x68u
#define AWG_SCHED_REG_TIME_RELOAD_LO    0x6Cu
#define AWG_SCHED_REG_TIME_RELOAD_HI    0x70u
#define AWG_SCHED_REG_TIME_RELOAD_CTRL  0x74u

#endif
