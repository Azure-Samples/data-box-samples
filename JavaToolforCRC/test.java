import java.io.*;

public class test {
        // The chunk-size for which we calculate CRCs
        // This could be arbitrary sizes
        static int chunk_size = 1 * 1024 * 1024;

        // Main takes a set of files as inputs, for computing CRC
        // The files should be accesible, interms of access and permissions
        // The files should be absolute path values
        // The test function gives the crc64 of each of the files in the same format as that of the BOM of databox
        public static void main(String[] args) throws FileNotFoundException, IOException
        {
                byte[] bytes = new byte[chunk_size];

                // Loop through the input files
                for (int i = 0; i < args.length; i++)
                {
                        // Open the file
                        File f = new File(args[i]);
                        FileInputStream fis = new FileInputStream(f);
                        long remaining = f.length();
                        int read_length = 0;
                        long crc = 0;

                        long crc_so_far = 0;
                        long length_so_far = 0;

                        // read in chunks and a final read of the remaining residue
                        while (remaining > 0)
                        {
                                read_length = (int)Math.min(chunk_size, remaining);
                                fis.read(bytes, 0, read_length);
                                // compute CRC for each buffer
                                crc = Crc64.compute(bytes, read_length);
                                // Concatenate with CRC so far
                                crc_so_far = Crc64.concatenate(crc_so_far, length_so_far, crc, read_length);
                                length_so_far += read_length;
                                remaining -= read_length;
                        }

                        // print the final CRC
			            String dq = "\"";
			            String s = "<file size=" + dq + length_so_far + dq + " crc64=" + dq  + Crc64.toString(crc_so_far) + dq + ">" + args[i] + "</file>";
			            System.out.println(s);
                }
        }
}
