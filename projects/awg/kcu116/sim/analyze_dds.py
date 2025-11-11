#!/usr/bin/env python3
"""
DDS Output Analyzer
Analyzes the CORDIC DDS output from simulation
"""

import numpy as np
import matplotlib.pyplot as plt
from scipy.fft import fft, fftfreq
import sys

def analyze_dds_output(filename='dds_output.txt', fs=200e6):
    """
    Analyze DDS output file
    
    Args:
        filename: Path to output file
        fs: Sample rate in Hz (default 200 MHz)
    """
    
    # Read data
    try:
        data = np.loadtxt(filename, dtype=np.int16)
    except:
        print(f"Error: Could not read {filename}")
        sys.exit(1)
    
    N = len(data)
    print(f"Loaded {N} samples")
    print(f"Sample rate: {fs/1e6:.1f} MHz")
    print(f"Duration: {N/fs*1e6:.2f} μs")
    
    # Convert to float
    data_float = data.astype(float)
    
    # Compute statistics
    print(f"\nStatistics:")
    print(f"  Mean: {np.mean(data_float):.2f}")
    print(f"  Std Dev: {np.std(data_float):.2f}")
    print(f"  Min: {np.min(data_float):.2f}")
    print(f"  Max: {np.max(data_float):.2f}")
    print(f"  Peak-to-Peak: {np.ptp(data_float):.2f}")
    
    # FFT analysis
    yf = fft(data_float)
    xf = fftfreq(N, 1/fs)[:N//2]
    magnitude = 2.0/N * np.abs(yf[0:N//2])
    
    # Find peaks
    threshold = np.max(magnitude) * 0.1
    peaks_idx = np.where(magnitude > threshold)[0]
    peaks_freq = xf[peaks_idx]
    peaks_mag = magnitude[peaks_idx]
    
    print(f"\nDetected Frequency Peaks:")
    for freq, mag in zip(peaks_freq, peaks_mag):
        if freq > 0:  # Skip DC
            print(f"  {freq/1e6:.3f} MHz: magnitude {mag:.1f}")
    
    # Create plots
    fig, axes = plt.subplots(3, 1, figsize=(12, 10))
    
    # Time domain - full
    ax = axes[0]
    time = np.arange(N) / fs * 1e6  # microseconds
    ax.plot(time, data_float, linewidth=0.5)
    ax.set_xlabel('Time (μs)')
    ax.set_ylabel('Amplitude')
    ax.set_title('DDS Output - Full Time Domain')
    ax.grid(True, alpha=0.3)
    
    # Time domain - zoomed
    ax = axes[1]
    zoom_samples = min(512, N)
    ax.plot(time[:zoom_samples], data_float[:zoom_samples])
    ax.set_xlabel('Time (μs)')
    ax.set_ylabel('Amplitude')
    ax.set_title(f'DDS Output - First {zoom_samples} Samples (Zoomed)')
    ax.grid(True, alpha=0.3)
    
    # Frequency domain
    ax = axes[2]
    ax.plot(xf/1e6, magnitude)
    ax.set_xlabel('Frequency (MHz)')
    ax.set_ylabel('Magnitude')
    ax.set_title('DDS Output - Frequency Spectrum')
    ax.set_xlim([0, fs/2/1e6])
    ax.grid(True, alpha=0.3)
    ax.set_yscale('log')
    
    # Mark peaks
    for freq, mag in zip(peaks_freq, peaks_mag):
        if freq > 0:
            ax.plot(freq/1e6, mag, 'ro', markersize=8)
            ax.annotate(f'{freq/1e6:.2f}MHz', 
                       xy=(freq/1e6, mag), 
                       xytext=(5, 5), 
                       textcoords='offset points',
                       fontsize=8)
    
    plt.tight_layout()
    plt.savefig('dds_analysis.png', dpi=150)
    print(f"\nPlot saved to dds_analysis.png")
    
    # Show plot
    plt.show()
    
    return data, xf, magnitude

if __name__ == '__main__':
    filename = sys.argv[1] if len(sys.argv) > 1 else 'dds_output.txt'
    analyze_dds_output(filename)
