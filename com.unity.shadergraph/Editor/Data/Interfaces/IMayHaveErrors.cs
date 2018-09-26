using System.Collections.Generic;
using UnityEditor;

namespace Data.Interfaces
{
    public interface IMayHaveErrors
    {
        bool hasErrors { get; }
        int errorCount { get; }

        IEnumerable<ShaderError> GetErrors();
        void AddError(ShaderError error);
        void AddErrors(IEnumerable<ShaderError> errors);
        void ClearErrors();
    }
}
